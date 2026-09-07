// SPDX-License-Identifier: 0BSD
/*
Workspace edit checkpoints for /undo of agent file writes.
*/

package tools

import "core:fmt"
import "core:io"
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
snapshot_run :: proc(argv: []string, cwd: string, allocator := context.allocator) -> (string, bool) {
	read_pipe, write_pipe, pipe_err := os.pipe()
	if pipe_err != nil {
		return "", false
	}
	defer os.close(read_pipe)
	process: os.Process
	{
		defer os.close(write_pipe)
		desc := os.Process_Desc{
			working_dir = cwd,
			command = argv,
			stdout = write_pipe,
			stderr = write_pipe,
		}
		start_err: os.Error
		process, start_err = os.process_start(desc)
		if start_err != nil {
			return "", false
		}
	}
	state, wait_err := os.process_wait(process)
	if wait_err != nil || !state.exited {
		return "", false
	}
	output: [dynamic]byte
	output.allocator = context.temp_allocator
	buffer: [4096]u8
	for {
		n, read_err := os.read(read_pipe, buffer[:])
		if n > 0 {
			append(&output, ..buffer[:n])
		}
		if n == 0 || read_err == io.Error.EOF || read_err == os.General_Error.Broken_Pipe {
			break
		}
		if read_err != nil {
			break
		}
	}
	return strings.clone(string(output[:]), allocator), state.exit_code == 0
}

@(private)
snapshot_git_args :: proc(dir, root: string, tail: []string, allocator := context.allocator) -> [dynamic]string {
	args := make([dynamic]string, 0, len(tail) + 3, allocator)
	append(&args, strings.clone("git", allocator))
	append(&args, fmt.aprintf("--git-dir=%s", dir, allocator = allocator))
	append(&args, fmt.aprintf("--work-tree=%s", root, allocator = allocator))
	for value in tail {
		append(&args, strings.clone(value, allocator))
	}
	return args
}

@(private)
snapshot_args_destroy :: proc(args: ^[dynamic]string) {
	for value in args {
		delete(value)
	}
	delete(args^)
	args^ = nil
}

@(private)
snapshot_git :: proc(dir, root: string, tail: []string, allocator := context.allocator) -> (string, bool) {
	args := snapshot_git_args(dir, root, tail, context.temp_allocator)
	return snapshot_run(args[:], root, allocator)
}

@(private)
snapshot_relative :: proc(abs_path, root: string) -> (string, bool) {
	if !strings.has_prefix(abs_path, root) {
		return "", false
	}
	relative := abs_path[len(root):]
	for len(relative) > 0 && (relative[0] == '/' || relative[0] == '\\') {
		relative = relative[1:]
	}
	return relative, len(relative) > 0
}

@(private)
snapshot_shadow_init :: proc(dir, root: string) -> bool {
	head, _ := filepath.join({dir, "HEAD"}, context.temp_allocator)
	if os.exists(head) {
		return true
	}
	if os.make_directory_all(dir) != nil {
		return false
	}
	out, ok := snapshot_git(dir, root, []string{"init"}, context.temp_allocator)
	_ = out
	if !ok {
		return false
	}
	_, _ = snapshot_git(dir, root, []string{"config", "user.name", "nullray"}, context.temp_allocator)
	_, _ = snapshot_git(dir, root, []string{"config", "user.email", "nullray@localhost"}, context.temp_allocator)
	return true
}

@(private)
snapshot_shadow_create :: proc(
	abs_path, dir, root: string,
	allocator := context.allocator,
) -> (commit, ref_name: string, ok: bool) {
	relative, rel_ok := snapshot_relative(abs_path, root)
	if !rel_ok || !snapshot_shadow_init(dir, root) {
		return "", "", false
	}
	_, add_ok := snapshot_git(dir, root, []string{"add", "-f", "-A", "--", relative}, context.temp_allocator)
	if !add_ok {
		return "", "", false
	}
	tree_out, tree_ok := snapshot_git(dir, root, []string{"write-tree"}, context.temp_allocator)
	if !tree_ok {
		return "", "", false
	}
	tree := strings.trim_space(tree_out)
	commit_out, commit_ok := snapshot_git(
		dir,
		root,
		[]string{"commit-tree", tree, "-m", "nullray checkpoint"},
		context.temp_allocator,
	)
	if !commit_ok {
		return "", "", false
	}
	hash := strings.trim_space(commit_out)
	ref := fmt.tprintf(
		"refs/nullray/%d-%d-%d",
		time.time_to_unix(time.now()),
		os.get_pid(),
		g_snap_id,
	)
	_, ref_ok := snapshot_git(dir, root, []string{"update-ref", ref, hash}, context.temp_allocator)
	if !ref_ok {
		return "", "", false
	}
	return strings.clone(hash, allocator), strings.clone(ref, allocator), true
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

undo_last_write :: proc(allocator := context.allocator) -> (msg: string, ok: bool) {
	sync.mutex_lock(&g_snap_mu)
	defer sync.mutex_unlock(&g_snap_mu)
	if len(g_snaps) == 0 {
		return strings.clone("nothing to undo", allocator), false
	}
	e := g_snaps[len(g_snaps) - 1]
	pop(&g_snaps)
	defer {
		snapshot_entry_destroy(&e)
	}
	if e.created {
		_ = os.remove(e.abs_path)
		return fmt.aprintf("undid create %s", e.abs_path, allocator = allocator), true
	}
	if e.shadow {
		dir := snapshot_dir(context.temp_allocator)
		root := workspace_root(context.temp_allocator)
		relative, rel_ok := snapshot_relative(e.abs_path, root)
		if !rel_ok {
			return strings.clone("undo checkpoint path invalid", allocator), false
		}
		spec := fmt.tprintf("%s:%s", e.commit, relative)
		data, show_ok := snapshot_git(dir, root, []string{"show", spec}, context.temp_allocator)
		if !show_ok {
			return strings.clone("undo checkpoint missing", allocator), false
		}
		if os.write_entire_file(e.abs_path, transmute([]u8)data) != nil {
			return strings.clone("undo write failed", allocator), false
		}
		return fmt.aprintf("restored %s", e.abs_path, allocator = allocator), true
	}
	data, err := os.read_entire_file(e.backup, context.temp_allocator)
	if err != nil {
		return strings.clone("undo backup missing", allocator), false
	}
	if os.write_entire_file(e.abs_path, data) != nil {
		return strings.clone("undo write failed", allocator), false
	}
	return fmt.aprintf("restored %s", e.abs_path, allocator = allocator), true
}

checkpoint_list :: proc(allocator := context.allocator) -> string {
	sync.mutex_lock(&g_snap_mu)
	defer sync.mutex_unlock(&g_snap_mu)
	if len(g_snaps) == 0 {
		return strings.clone("(no checkpoints)", allocator)
	}
	b: strings.Builder
	strings.builder_init(&b, allocator)
	start := max(0, len(g_snaps) - 10)
	for i := len(g_snaps) - 1; i >= start; i -= 1 {
		kind := g_snaps[i].shadow ? "shadow" : "backup"
		fmt.sbprintf(&b, "%d %s %s\n", i + 1, kind, g_snaps[i].abs_path)
	}
	return strings.to_string(b)
}

checkpoint_restore :: proc(id: int, allocator := context.allocator) -> (msg: string, ok: bool) {
	sync.mutex_lock(&g_snap_mu)
	defer sync.mutex_unlock(&g_snap_mu)
	if id < 1 || id > len(g_snaps) {
		return strings.clone("checkpoint id out of range", allocator), false
	}
	idx := id - 1
	e := g_snaps[idx]
	ordered_remove(&g_snaps, idx)
	defer snapshot_entry_destroy(&e)
	if e.created {
		_ = os.remove(e.abs_path)
		return fmt.aprintf("restored by removing create %s", e.abs_path, allocator = allocator), true
	}
	if e.shadow {
		dir := snapshot_dir(context.temp_allocator)
		root := workspace_root(context.temp_allocator)
		relative, rel_ok := snapshot_relative(e.abs_path, root)
		if !rel_ok {
			return strings.clone("checkpoint path invalid", allocator), false
		}
		spec := fmt.tprintf("%s:%s", e.commit, relative)
		data, show_ok := snapshot_git(dir, root, []string{"show", spec}, context.temp_allocator)
		if !show_ok {
			return strings.clone("checkpoint missing", allocator), false
		}
		if os.write_entire_file(e.abs_path, transmute([]u8)data) != nil {
			return strings.clone("checkpoint restore write failed", allocator), false
		}
		return fmt.aprintf("restored checkpoint %d %s", id, e.abs_path, allocator = allocator), true
	}
	data, err := os.read_entire_file(e.backup, context.temp_allocator)
	if err != nil {
		return strings.clone("checkpoint backup missing", allocator), false
	}
	if os.write_entire_file(e.abs_path, data) != nil {
		return strings.clone("checkpoint restore write failed", allocator), false
	}
	return fmt.aprintf("restored checkpoint %d %s", id, e.abs_path, allocator = allocator), true
}

checkpoint_diff :: proc(id: int, allocator := context.allocator) -> (msg: string, ok: bool) {
	sync.mutex_lock(&g_snap_mu)
	defer sync.mutex_unlock(&g_snap_mu)
	if id < 1 || id > len(g_snaps) {
		return strings.clone("checkpoint id out of range", allocator), false
	}
	e := g_snaps[id - 1]
	if e.shadow {
		dir := snapshot_dir(context.temp_allocator)
		root := workspace_root(context.temp_allocator)
		relative, rel_ok := snapshot_relative(e.abs_path, root)
		if !rel_ok {
			return strings.clone("checkpoint path invalid", allocator), false
		}
		out, diff_ok := snapshot_git(
			dir,
			root,
			[]string{"diff", e.commit, "--", relative},
			allocator,
		)
		if !diff_ok {
			return strings.clone("checkpoint diff failed", allocator), false
		}
		if len(strings.trim_space(out)) == 0 {
			delete(out)
			return fmt.aprintf("checkpoint %d matches working tree for %s", id, e.abs_path, allocator = allocator), true
		}
		return out, true
	}
	data, err := os.read_entire_file(e.backup, context.temp_allocator)
	if err != nil {
		return strings.clone("checkpoint backup missing", allocator), false
	}
	cur, cerr := os.read_entire_file(e.abs_path, context.temp_allocator)
	if cerr != nil {
		return fmt.aprintf("checkpoint %d backup exists, working file missing: %s", id, e.abs_path, allocator = allocator), true
	}
	if string(data) == string(cur) {
		return fmt.aprintf("checkpoint %d matches working tree for %s", id, e.abs_path, allocator = allocator), true
	}
	return fmt.aprintf(
		"checkpoint %d differs from working tree for %s (backup %d bytes, file %d bytes)",
		id,
		e.abs_path,
		len(data),
		len(cur),
		allocator = allocator,
	), true
}

snapshots_destroy :: proc() {
	sync.mutex_lock(&g_snap_mu)
	for &entry in g_snaps {
		snapshot_entry_destroy(&entry)
	}
	delete(g_snaps)
	g_snaps = nil
	g_snap_id = 0
	sync.mutex_unlock(&g_snap_mu)
}
