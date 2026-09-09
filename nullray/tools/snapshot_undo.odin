// SPDX-License-Identifier: 0BSD
/*
Undo and checkpoint list/restore/diff for workspace snapshots.
*/

package tools

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:sync"

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
