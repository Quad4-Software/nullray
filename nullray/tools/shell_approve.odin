// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
One-shot shell approval for NULLRAY_PERMS=ask.
*/

package tools

import "base:runtime"
import "core:sync"
import "core:strings"

g_pending_mu: sync.Mutex
g_pending_cmd: string
g_once_allow: string

shell_set_pending :: proc(cmd: string) {
	sync.mutex_lock(&g_pending_mu)
	defer sync.mutex_unlock(&g_pending_mu)
	if len(g_pending_cmd) > 0 {
		delete(g_pending_cmd, runtime.heap_allocator())
	}
	// Global state must outlive the caller's allocator (test tracking arenas
	// are torn down between tests).
	g_pending_cmd = strings.clone(cmd, runtime.heap_allocator())
}

shell_pending :: proc(allocator := context.allocator) -> string {
	sync.mutex_lock(&g_pending_mu)
	defer sync.mutex_unlock(&g_pending_mu)
	if len(g_pending_cmd) == 0 {
		return ""
	}
	return strings.clone(g_pending_cmd, allocator)
}

shell_allow_once :: proc() -> (cmd: string, ok: bool) {
	sync.mutex_lock(&g_pending_mu)
	defer sync.mutex_unlock(&g_pending_mu)
	if len(g_pending_cmd) == 0 {
		return "", false
	}
	if len(g_once_allow) > 0 {
		delete(g_once_allow, runtime.heap_allocator())
	}
	g_once_allow = strings.clone(g_pending_cmd, runtime.heap_allocator())
	cmd = strings.clone(g_pending_cmd)
	delete(g_pending_cmd, runtime.heap_allocator())
	g_pending_cmd = {}
	return cmd, true
}

shell_deny_pending :: proc() {
	sync.mutex_lock(&g_pending_mu)
	defer sync.mutex_unlock(&g_pending_mu)
	if len(g_pending_cmd) > 0 {
		delete(g_pending_cmd, runtime.heap_allocator())
	}
	g_pending_cmd = {}
	// A stale once-allow must not survive a deny of the pending prompt.
	if len(g_once_allow) > 0 {
		delete(g_once_allow, runtime.heap_allocator())
	}
	g_once_allow = {}
}

shell_consume_once_allow :: proc(cmd: string) -> bool {
	sync.mutex_lock(&g_pending_mu)
	defer sync.mutex_unlock(&g_pending_mu)
	if len(g_once_allow) == 0 {
		return false
	}
	if strings.trim_space(cmd) == strings.trim_space(g_once_allow) {
		delete(g_once_allow, runtime.heap_allocator())
		g_once_allow = {}
		return true
	}
	return false
}
