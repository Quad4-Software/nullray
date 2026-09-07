// SPDX-License-Identifier: 0BSD
/*
Workspace edit snapshots for /undo of agent file writes.
*/

package tools

import "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "nullray:sandbox"

Snap_Entry :: struct {
	abs_path: string,
	backup:   string,
	created:  bool,
}

g_snap_mu: sync.Mutex
g_snaps: [dynamic]Snap_Entry

snapshot_dir :: proc(allocator := context.allocator) -> string {
	cfg := sandbox.resolve_config_dir(context.temp_allocator)
	return fmt.aprintf("%s/snapshots", cfg, allocator = allocator)
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

snapshot_before_write :: proc(abs_path: string) {
	sync.mutex_lock(&g_snap_mu)
	defer sync.mutex_unlock(&g_snap_mu)
	dir := snapshot_dir(context.temp_allocator)
	_ = os.make_directory_all(dir)
	backup := fmt.aprintf("%s/%s.bak", dir, snap_name(abs_path), allocator = context.allocator)
	created := false
	if os.exists(abs_path) {
		data, err := os.read_entire_file(abs_path, context.temp_allocator)
		if err == nil {
			_ = os.write_entire_file(backup, data)
		}
	} else {
		created = true
		_ = os.write_entire_file(backup, []u8{})
	}
	append(&g_snaps, Snap_Entry{
		abs_path = strings.clone(abs_path),
		backup = backup,
		created = created,
	})
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
		delete(e.abs_path)
		delete(e.backup)
	}
	if e.created {
		_ = os.remove(e.abs_path)
		return fmt.aprintf("undid create %s", e.abs_path, allocator = allocator), true
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
