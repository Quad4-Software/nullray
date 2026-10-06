// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Undo and checkpoint list/restore/diff for workspace snapshots.
*/

package tools

import "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"

/*
Restore one recorded file: created files get removed, shadow files are written
back from their pre-write blob, backup files are copied back.
*/
@(private)
snap_file_restore :: proc(f: ^Snap_File) -> (err: string) {
	if f.created {
		_ = os.remove(f.abs_path)
		return ""
	}
	if len(f.commit) > 0 {
		dir := snapshot_dir(context.temp_allocator)
		root := workspace_root(context.temp_allocator)
		relative, rel_ok := snapshot_relative(f.abs_path, root)
		if !rel_ok {
			return "path invalid"
		}
		spec := fmt.tprintf("%s:%s", f.commit, relative)
		data, show_ok := snapshot_git(dir, root, []string{"show", spec}, context.temp_allocator)
		if !show_ok {
			return "blob missing"
		}
		if werr := tool_write_atomic(f.abs_path, transmute([]u8)data); len(werr) > 0 {
			return "write failed"
		}
		return ""
	}
	if len(f.backup) > 0 {
		data, rerr := os.read_entire_file(f.backup, context.temp_allocator)
		if rerr != nil {
			return "backup missing"
		}
		if werr := tool_write_atomic(f.abs_path, data); len(werr) > 0 {
			return "write failed"
		}
		return ""
	}
	return ""
}

/*
Restore an entry's exact file set in reverse record order so the earliest
pre-batch state wins when a path was written twice in one batch.
*/
@(private)
snap_entry_restore :: proc(e: ^Snap_Entry) -> (restored: int, first_err: string) {
	for i := len(e.files) - 1; i >= 0; i -= 1 {
		if ferr := snap_file_restore(&e.files[i]); len(ferr) > 0 && len(first_err) == 0 {
			first_err = ferr
		} else if len(ferr) == 0 {
			restored += 1
		}
	}
	return restored, first_err
}

undo_last_write :: proc(allocator := context.allocator) -> (msg: string, ok: bool) {
	sync.mutex_lock(&g_snap_mu)
	defer sync.mutex_unlock(&g_snap_mu)
	snapshot_flush_locked(0)
	if len(g_snaps) == 0 {
		return strings.clone("nothing to undo", allocator), false
	}
	e := g_snaps[len(g_snaps) - 1]
	pop(&g_snaps)
	defer {
		snapshot_entry_destroy(&e)
	}
	restored, ferr := snap_entry_restore(&e)
	if len(ferr) > 0 {
		return fmt.aprintf("undo partial: %s (%s)", ferr, e.label, allocator = allocator), false
	}
	return fmt.aprintf("undid %s", e.label, allocator = allocator), true
}

@(private)
snap_human_bytes :: proc(n: i64, allocator := context.temp_allocator) -> string {
	switch {
	case n >= 1 << 20:
		return fmt.aprintf("%.1f MB", f64(n) / (1 << 20), allocator = allocator)
	case n >= 1 << 10:
		return fmt.aprintf("%.1f KB", f64(n) / (1 << 10), allocator = allocator)
	}
	return fmt.aprintf("%d B", n, allocator = allocator)
}

checkpoint_list :: proc(allocator := context.allocator) -> string {
	sync.mutex_lock(&g_snap_mu)
	defer sync.mutex_unlock(&g_snap_mu)
	snapshot_flush_locked(0)
	if len(g_snaps) == 0 {
		return strings.clone("(no checkpoints)", allocator)
	}
	b: strings.Builder
	strings.builder_init(&b, allocator)
	start := max(0, len(g_snaps) - 10)
	for i := len(g_snaps) - 1; i >= start; i -= 1 {
		e := &g_snaps[i]
		kind := e.shadow ? "shadow" : "backup"
		size := snap_human_bytes(e.bytes)
		fmt.sbprintf(&b, "%d %s %s ~%s\n", i + 1, kind, e.label, size)
		for f in e.files {
			suffix := f.created ? " (new)" : ""
			fmt.sbprintf(&b, "    %s%s\n", f.abs_path, suffix)
		}
	}
	if g_shadow_pruned > 0 {
		fmt.sbprintf(&b, "(shadow repo pruned %d old checkpoints over the size cap)\n", g_shadow_pruned)
	}
	return strings.to_string(b)
}

checkpoint_restore :: proc(id: int, allocator := context.allocator) -> (msg: string, ok: bool) {
	sync.mutex_lock(&g_snap_mu)
	defer sync.mutex_unlock(&g_snap_mu)
	snapshot_flush_locked(0)
	if id < 1 || id > len(g_snaps) {
		return strings.clone("checkpoint id out of range", allocator), false
	}
	idx := id - 1
	e := g_snaps[idx]
	ordered_remove(&g_snaps, idx)
	defer snapshot_entry_destroy(&e)
	restored, ferr := snap_entry_restore(&e)
	if len(ferr) > 0 {
		return fmt.aprintf("restored checkpoint %d partially: %s (%d of %d files)", id, ferr, restored, len(e.files), allocator = allocator), false
	}
	return fmt.aprintf("restored checkpoint %d %s", id, e.label, allocator = allocator), true
}

checkpoint_diff :: proc(id: int, allocator := context.allocator) -> (msg: string, ok: bool) {
	sync.mutex_lock(&g_snap_mu)
	defer sync.mutex_unlock(&g_snap_mu)
	snapshot_flush_locked(0)
	if id < 1 || id > len(g_snaps) {
		return strings.clone("checkpoint id out of range", allocator), false
	}
	e := &g_snaps[id - 1]
	dir := snapshot_dir(context.temp_allocator)
	root := workspace_root(context.temp_allocator)
	b: strings.Builder
	strings.builder_init(&b, allocator)
	diffs := 0
	for &f in e.files {
		if f.created {
			if os.exists(f.abs_path) {
				fmt.sbprintf(&b, "new file since checkpoint: %s\n", f.abs_path)
				diffs += 1
			}
			continue
		}
		if len(f.commit) > 0 {
			relative, rel_ok := snapshot_relative(f.abs_path, root)
			if !rel_ok {
				continue
			}
			out, diff_ok := snapshot_git(dir, root, []string{"diff", f.commit, "--", relative}, context.temp_allocator)
			if !diff_ok {
				continue
			}
			if len(strings.trim_space(out)) > 0 {
				strings.write_string(&b, out)
				diffs += 1
			}
			continue
		}
		if len(f.backup) > 0 {
			data, rerr := os.read_entire_file(f.backup, context.temp_allocator)
			if rerr != nil {
				continue
			}
			cur, cerr := os.read_entire_file(f.abs_path, context.temp_allocator)
			if cerr != nil {
				fmt.sbprintf(&b, "checkpoint backup exists, working file missing: %s\n", f.abs_path)
				diffs += 1
				continue
			}
			if string(data) != string(cur) {
				fmt.sbprintf(&b, "checkpoint differs from working tree for %s (backup %d bytes, file %d bytes)\n", f.abs_path, len(data), len(cur))
				diffs += 1
			}
		}
	}
	body := strings.to_string(b)
	if diffs == 0 {
		delete(body)
		return fmt.aprintf("checkpoint %d %s matches working tree", id, e.label, allocator = allocator), true
	}
	if len(body) == 0 {
		delete(body)
		return strings.clone("checkpoint diff failed", allocator), false
	}
	return body, true
}

snapshots_destroy :: proc() {
	sync.mutex_lock(&g_snap_mu)
	for &entry in g_snaps {
		snapshot_entry_destroy(&entry)
	}
	delete(g_snaps)
	g_snaps = nil
	for &f in g_pending {
		snap_file_destroy(&f)
	}
	delete(g_pending)
	g_pending = nil
	g_snap_id = 0
	g_ckpt_id = 0
	g_snaps_since_gc = 0
	g_shadow_pruned = 0
	sync.mutex_unlock(&g_snap_mu)
}
