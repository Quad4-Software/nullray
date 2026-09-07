// SPDX-License-Identifier: 0BSD
/*
One-shot shell approval for NULLRAY_PERMS=ask.
*/

package tools

import "core:sync"
import "core:strings"

g_pending_mu: sync.Mutex
g_pending_cmd: string
g_once_allow: string

shell_set_pending :: proc(cmd: string) {
	sync.mutex_lock(&g_pending_mu)
	defer sync.mutex_unlock(&g_pending_mu)
	if len(g_pending_cmd) > 0 {
		delete(g_pending_cmd)
	}
	g_pending_cmd = strings.clone(cmd)
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
		delete(g_once_allow)
	}
	g_once_allow = strings.clone(g_pending_cmd)
	cmd = strings.clone(g_pending_cmd)
	delete(g_pending_cmd)
	g_pending_cmd = {}
	return cmd, true
}

shell_deny_pending :: proc() {
	sync.mutex_lock(&g_pending_mu)
	defer sync.mutex_unlock(&g_pending_mu)
	if len(g_pending_cmd) > 0 {
		delete(g_pending_cmd)
	}
	g_pending_cmd = {}
}

shell_consume_once_allow :: proc(cmd: string) -> bool {
	sync.mutex_lock(&g_pending_mu)
	defer sync.mutex_unlock(&g_pending_mu)
	if len(g_once_allow) == 0 {
		return false
	}
	if strings.trim_space(cmd) == strings.trim_space(g_once_allow) {
		delete(g_once_allow)
		g_once_allow = {}
		return true
	}
	return false
}
