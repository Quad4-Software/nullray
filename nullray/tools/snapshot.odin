// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Workspace edit checkpoints for /undo and /checkpoint of agent file writes.

Writes snapshot pre-edit state into a shadow git repo (content addressed, so
repeated blobs dedupe) and group into one labeled entry per agent step. When
the shadow repo is unavailable each file falls back to a single backup copy.
*/

package tools

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:time"
import "nullray:constants"
import "nullray:sandbox"

// One file's pre-write state inside a checkpoint entry.
Snap_File :: struct {
	abs_path: string,
	commit:   string, // shadow commit holding the pre-write blob
	ref_name: string, // per-file ref keeping that commit reachable
	backup:   string, // fallback copy used only when shadow init failed
	created:  bool,   // file did not exist before the write
	size:     i64,    // file size at snapshot time (approx stored bytes)
}

// One labeled checkpoint covering every file a tool batch wrote.
Snap_Entry :: struct {
	id:       u64,
	label:    string, // "step N - M files"
	files:    [dynamic]Snap_File,
	commit:   string, // batch anchor commit (tree = pre-batch index)
	ref_name: string, // refs/nullray/ckpt-<id>
	shadow:   bool,
	bytes:    i64, // sum of recorded file sizes
}

SNAPSHOT_MAX_FILE_BYTES :: 8 << 20 // skip snapshotting files larger than this
SNAPSHOT_GC_INTERVAL :: 25 // flushes between gc --auto and size checks
SNAPSHOT_MAX_SHADOW_KB :: 256 * 1024 // 256 MiB shadow repo cap
SNAPSHOT_MIN_KEEP :: 10 // size-cap prune never drops below this many entries

g_snap_mu: sync.Mutex
g_snaps: [dynamic]Snap_Entry
g_pending: [dynamic]Snap_File
g_snap_id: u64
g_ckpt_id: u64
g_snaps_since_gc: int
g_shadow_pruned: int

snapshot_dir :: proc(allocator := context.allocator) -> string {
	root := workspace_root(context.temp_allocator)
	path, err := filepath.join({root, constants.SHADOW_DIR}, allocator)
	if err != nil {
		return fmt.aprintf("%s/%s", root, constants.SHADOW_DIR, allocator = allocator)
	}
	return path
}

/*
NULLRAY_CHECKPOINT_AUTO gates automatic snapshots. Default on. A "0" (or
false/no/off) disables recording; manual /checkpoint list/restore/diff still
works on entries already taken.
*/
snapshot_auto_enabled :: proc() -> bool {
	if raw, ok := os.lookup_env(constants.ENV_CHECKPOINT_AUTO, context.temp_allocator); ok {
		switch strings.to_lower(strings.trim_space(raw), context.temp_allocator) {
		case "0", "false", "no", "off", "disable", "disabled":
			return false
		}
	}
	return true
}

/*
Skip paths that would bloat or corrupt the checkpoint store: anything under
.nullray (shadow repo, artifacts, worktrees, board, todos) or .git internals.
*/
@(private)
snapshot_path_skipped :: proc(abs_path, root: string) -> bool {
	relative, ok := snapshot_relative(abs_path, root)
	if !ok {
		return false
	}
	rel, _ := strings.replace_all(relative, "\\", "/", context.temp_allocator)
	if rel == ".nullray" || rel == ".git" {
		return true
	}
	if strings.has_prefix(rel, ".nullray/") || strings.has_prefix(rel, ".git/") {
		return true
	}
	return strings.contains(rel, "/.git/") || strings.contains(rel, "/.nullray/")
}

@(private)
snap_name :: proc(abs_path: string, allocator := context.temp_allocator) -> string {
	h: u64 = 14695981039346656037
	for b in transmute([]u8)abs_path {
		h ~= u64(b)
		h *= 1099511628211
	}
	return fmt.aprintf("%x", h, allocator = allocator)
}

@(private)
snapshot_keep :: proc() -> int {
	if raw, ok := os.lookup_env(constants.ENV_CHECKPOINT_KEEP, context.temp_allocator); ok {
		if value, parsed := strconv.parse_int(strings.trim_space(raw)); parsed && value > 0 {
			return value
		}
	}
	return constants.DEFAULT_CHECKPOINT_KEEP
}

@(private)
snap_file_destroy :: proc(f: ^Snap_File) {
	allocator := os.heap_allocator()
	delete(f.abs_path, allocator)
	delete(f.commit, allocator)
	delete(f.ref_name, allocator)
	delete(f.backup, allocator)
	f^ = {}
}

@(private)
snapshot_entry_destroy :: proc(entry: ^Snap_Entry, remove_files := true) {
	if remove_files {
		dir := snapshot_dir(context.temp_allocator)
		root := workspace_root(context.temp_allocator)
		for &f in entry.files {
			if len(f.backup) > 0 {
				_ = os.remove(f.backup)
			}
			if len(f.ref_name) > 0 {
				_, _ = snapshot_git(dir, root, []string{"update-ref", "-d", f.ref_name}, context.temp_allocator)
			}
		}
		if len(entry.ref_name) > 0 {
			_, _ = snapshot_git(dir, root, []string{"update-ref", "-d", entry.ref_name}, context.temp_allocator)
		}
	}
	allocator := os.heap_allocator()
	for &f in entry.files {
		snap_file_destroy(&f)
	}
	delete(entry.files)
	delete(entry.label, allocator)
	delete(entry.commit, allocator)
	delete(entry.ref_name, allocator)
	entry^ = {}
}

/*
Enforce NULLRAY_CHECKPOINT_KEEP on entry count. Ref deletion drops
reachability; the periodic gc in snapshot_gc_maybe_locked reclaims objects so
each prune does not pay for a full repack.
*/
@(private)
snapshot_prune :: proc() {
	keep := snapshot_keep()
	for len(g_snaps) > keep {
		entry := g_snaps[0]
		ordered_remove(&g_snaps, 0)
		snapshot_entry_destroy(&entry)
	}
}

/*
Occasional maintenance: git gc --auto every SNAPSHOT_GC_INTERVAL flushes, then
a bounded prune when the shadow repo exceeds SNAPSHOT_MAX_SHADOW_KB. The cap
loop drops the oldest entries down to SNAPSHOT_MIN_KEEP at most.
*/
@(private)
snapshot_gc_maybe_locked :: proc() {
	g_snaps_since_gc += 1
	if g_snaps_since_gc < SNAPSHOT_GC_INTERVAL {
		return
	}
	g_snaps_since_gc = 0
	dir := snapshot_dir(context.temp_allocator)
	root := workspace_root(context.temp_allocator)
	_, _ = snapshot_git(dir, root, []string{"gc", "--auto"}, context.temp_allocator)
	kb := snapshot_shadow_size_kb(dir, root)
	if kb <= 0 || kb <= SNAPSHOT_MAX_SHADOW_KB {
		return
	}
	for _ in 0 ..< 4 {
		if len(g_snaps) <= SNAPSHOT_MIN_KEEP {
			break
		}
		drop := max(1, (len(g_snaps) - SNAPSHOT_MIN_KEEP) / 2)
		for _ in 0 ..< drop {
			entry := g_snaps[0]
			ordered_remove(&g_snaps, 0)
			snapshot_entry_destroy(&entry)
			g_shadow_pruned += 1
		}
		_, _ = snapshot_git(dir, root, []string{"reflog", "expire", "--expire=now", "--all"}, context.temp_allocator)
		_, _ = snapshot_git(dir, root, []string{"gc", "--prune=now"}, context.temp_allocator)
		kb = snapshot_shadow_size_kb(dir, root)
		if kb <= SNAPSHOT_MAX_SHADOW_KB {
			break
		}
	}
}

/*
Record a file's pre-write state. Called by write tools before touching disk.
Records stack in g_pending until checkpoint_commit_step folds them into one
labeled entry, so a batch writes one checkpoint instead of one per file.
Repeat writes to the same path inside a batch keep the earliest pre-state.
*/
snapshot_before_write :: proc(abs_path: string) {
	if !snapshot_auto_enabled() {
		return
	}
	if sandbox.path_is_secret_blocked(abs_path) {
		return
	}
	root := workspace_root(context.temp_allocator)
	if snapshot_path_skipped(abs_path, root) {
		return
	}
	sync.mutex_lock(&g_snap_mu)
	defer sync.mutex_unlock(&g_snap_mu)
	if g_pending == nil {
		g_pending = make([dynamic]Snap_File, os.heap_allocator())
	}
	for f in g_pending {
		if f.abs_path == abs_path {
			return
		}
	}
	g_snap_id += 1
	allocator := os.heap_allocator()
	dir := snapshot_dir(context.temp_allocator)
	_ = sandbox.mkdir_all(dir)
	created := false
	size: i64 = 0
	if st, stat_err := os.stat(abs_path, context.temp_allocator); stat_err == nil {
		size = st.size
	} else {
		created = true
	}
	if !created && size > SNAPSHOT_MAX_FILE_BYTES {
		return
	}
	if created {
		// Nothing to capture; restore just removes the file.
		append(&g_pending, Snap_File{
			abs_path = strings.clone(abs_path, allocator),
			created = true,
		})
		return
	}
	commit, ref_name, shadow_ok := snapshot_shadow_create(abs_path, dir, root, allocator)
	if shadow_ok {
		append(&g_pending, Snap_File{
			abs_path = strings.clone(abs_path, allocator),
			commit = commit,
			ref_name = ref_name,
			size = size,
		})
		return
	}
	backups, _ := filepath.join({dir, "backups"}, context.temp_allocator)
	_ = sandbox.mkdir_all(backups)
	backup := fmt.aprintf(
		"%s/%s-%d-%d-%d.bak",
		backups,
		snap_name(abs_path),
		time.time_to_unix(time.now()),
		os.get_pid(),
		g_snap_id,
		allocator = allocator,
	)
	data, err := os.read_entire_file(abs_path, context.temp_allocator)
	if err != nil || os.write_entire_file(backup, data) != nil {
		delete(backup, allocator)
		return
	}
	append(&g_pending, Snap_File{
		abs_path = strings.clone(abs_path, allocator),
		backup = backup,
		size = size,
	})
}

/*
Fold pending pre-write records into one labeled checkpoint entry. Called once
per agent step after the tool batch completes (step <= 0 labels the entry as
a bare writes group for non-step callers). Also commits the pre-batch index
to the shadow repo as refs/nullray/ckpt-<id> so each entry is a real anchor.
*/
checkpoint_commit_step :: proc(step: int) {
	sync.mutex_lock(&g_snap_mu)
	defer sync.mutex_unlock(&g_snap_mu)
	snapshot_flush_locked(step)
}

@(private)
snapshot_flush_locked :: proc(step: int) {
	if len(g_pending) == 0 {
		return
	}
	if g_snaps == nil {
		g_snaps = make([dynamic]Snap_Entry, os.heap_allocator())
	}
	g_ckpt_id += 1
	allocator := os.heap_allocator()
	n := len(g_pending)
	label := ""
	if step > 0 {
		label = fmt.aprintf("step %d - %d files", step, n, allocator = allocator)
	} else {
		label = fmt.aprintf("writes - %d files", n, allocator = allocator)
	}
	shadow := false
	total: i64 = 0
	for f in g_pending {
		if len(f.commit) > 0 {
			shadow = true
		}
		total += f.size
	}
	commit, ref_name := "", ""
	if shadow {
		dir := snapshot_dir(context.temp_allocator)
		root := workspace_root(context.temp_allocator)
		msg := fmt.tprintf("nullray %s", label)
		commit, ref_name = snapshot_shadow_commit(dir, root, g_ckpt_id, msg, allocator)
	}
	append(&g_snaps, Snap_Entry{
		id = g_ckpt_id,
		label = label,
		files = g_pending,
		commit = commit,
		ref_name = ref_name,
		shadow = shadow,
		bytes = total,
	})
	g_pending = nil
	snapshot_prune()
	snapshot_gc_maybe_locked()
}
