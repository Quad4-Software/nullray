// SPDX-License-Identifier: 0BSD
/*
Track live shell process trees so Esc/stop can kill them.
*/

package tools

import "core:os"
import "core:sync"

@(private)
Shell_Active :: struct {
	process: os.Process
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
		g_shells = make([dynamic]Shell_Active)
	}
	append(&g_shells, Shell_Active{process = process})
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

shell_cancel_active :: proc() {
	sync.mutex_lock(&g_shell_mu)
	snapshot := make([]Shell_Active, len(g_shells), context.temp_allocator)
	copy(snapshot, g_shells[:])
	sync.mutex_unlock(&g_shell_mu)
	for s in snapshot {
		shell_kill_process_tree(s.process)
	}
}
