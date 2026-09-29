// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Track live shell process trees so Esc/stop can kill them. Each process is
owned by the session bound to its worker thread, so cancelling one tab kills
only that tab's shells.
*/

package tools

import "core:os"
import "core:sync"
import "base:runtime"
import "nullray:http"

@(private)
Shell_Active :: struct {
	process: os.Process,
	owner:   rawptr,
}

@(private)
g_shell_mu: sync.Mutex
@(private)
g_shells: [dynamic]Shell_Active

shell_register_active :: proc(process: os.Process) {
	if process.pid <= 0 {
		return
	}
	sync.mutex_lock(&g_shell_mu)
	defer sync.mutex_unlock(&g_shell_mu)
	if g_shells == nil {
		g_shells = make([dynamic]Shell_Active, 0, runtime.heap_allocator())
	}
	append(&g_shells, Shell_Active{process = process, owner = http.owner_for_thread()})
}

shell_clear_active :: proc(process: os.Process) {
	if process.pid <= 0 {
		return
	}
	sync.mutex_lock(&g_shell_mu)
	defer sync.mutex_unlock(&g_shell_mu)
	for i := len(g_shells) - 1; i >= 0; i -= 1 {
		if g_shells[i].process.pid == process.pid {
			ordered_remove(&g_shells, i)
			return
		}
	}
}

shell_cancel_active :: proc(owner: rawptr = nil) {
	owner := http.resolve_owner(owner)
	if owner == nil {
		return
	}
	sync.mutex_lock(&g_shell_mu)
	snapshot := make([dynamic]Shell_Active, 0, len(g_shells), context.temp_allocator)
	for s in g_shells {
		if s.owner == owner {
			append(&snapshot, s)
		}
	}
	sync.mutex_unlock(&g_shell_mu)
	for s in snapshot {
		shell_kill_process_tree(s.process)
	}
}
