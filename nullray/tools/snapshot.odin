// SPDX-License-Identifier: 0BSD
/*
Workspace edit checkpoints for /undo of agent file writes.
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

Snap_Entry :: struct {
	abs_path: string,
	backup:   string,
	commit:   string,
	ref_name: string,
	created:  bool,
	shadow:   bool,
}

g_snap_mu: sync.Mutex
g_snaps: [dynamic]Snap_Entry
g_snap_id: u64

snapshot_dir :: proc(allocator := context.allocator) -> string {
	root := workspace_root(context.temp_allocator)
	path, err := filepath.join({root, constants.SHADOW_DIR}, allocator)
	if err != nil {
		return fmt.aprintf("%s/%s", root, constants.SHADOW_DIR, allocator = allocator)
	}
	return path
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
snapshot_entry_destroy :: proc(entry: ^Snap_Entry, remove_files := true) {
	if remove_files && len(entry.backup) > 0 {
		_ = os.remove(entry.backup)
	}
	if remove_files && entry.shadow && len(entry.ref_name) > 0 {
		dir := snapshot_dir(context.temp_allocator)
		root := workspace_root(context.temp_allocator)
		_, _ = snapshot_git(dir, root, []string{"update-ref", "-d", entry.ref_name}, context.temp_allocator)
	}
	allocator := os.heap_allocator()
	delete(entry.abs_path, allocator)
	delete(entry.backup, allocator)
	delete(entry.commit, allocator)
	delete(entry.ref_name, allocator)
	entry^ = {}
}

@(private)
snapshot_prune :: proc() {
	keep := snapshot_keep()
	pruned := false
	for len(g_snaps) > keep {
		entry := g_snaps[0]
		ordered_remove(&g_snaps, 0)
		snapshot_entry_destroy(&entry)
		pruned = true
	}
	if pruned {
		dir := snapshot_dir(context.temp_allocator)
		root := workspace_root(context.temp_allocator)
		_, _ = snapshot_git(dir, root, []string{"reflog", "expire", "--expire=now", "--all"}, context.temp_allocator)
		_, _ = snapshot_git(dir, root, []string{"gc", "--prune=now"}, context.temp_allocator)
	}
}

snapshot_before_write :: proc(abs_path: string) {
	if sandbox.path_is_secret_blocked(abs_path) {
		return
	}
	sync.mutex_lock(&g_snap_mu)
	defer sync.mutex_unlock(&g_snap_mu)
	g_snap_id += 1
	allocator := os.heap_allocator()
	if g_snaps == nil {
		g_snaps = make([dynamic]Snap_Entry, allocator)
	}
	dir := snapshot_dir(context.temp_allocator)
	_ = os.make_directory_all(dir)
	created := false
	if !os.exists(abs_path) {
		created = true
	}
	root := workspace_root(context.temp_allocator)
	commit, ref_name, shadow_ok := snapshot_shadow_create(abs_path, dir, root, allocator)
	if shadow_ok {
		append(&g_snaps, Snap_Entry{
			abs_path = strings.clone(abs_path, allocator),
			commit = commit,
			ref_name = ref_name,
			created = created,
			shadow = true,
		})
		snapshot_prune()
		return
	}
	backups, _ := filepath.join({dir, "backups"}, context.temp_allocator)
	_ = os.make_directory_all(backups)
	backup := fmt.aprintf(
		"%s/%s-%d-%d-%d.bak",
		backups,
		snap_name(abs_path),
		time.time_to_unix(time.now()),
		os.get_pid(),
		g_snap_id,
		allocator = allocator,
	)
	if os.exists(abs_path) {
		data, err := os.read_entire_file(abs_path, context.temp_allocator)
		if err != nil {
			delete(backup, allocator)
			return
		}
		if os.write_entire_file(backup, data) != nil {
			delete(backup, allocator)
			return
		}
	} else {
		if os.write_entire_file(backup, []u8{}) != nil {
			delete(backup, allocator)
			return
		}
	}
	append(&g_snaps, Snap_Entry{
		abs_path = strings.clone(abs_path, allocator),
		backup = backup,
		created = created,
	})
	snapshot_prune()
}
