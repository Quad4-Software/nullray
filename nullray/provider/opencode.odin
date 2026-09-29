// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
OpenCode Zen and Go request headers for routing and session affinity.
*/

package provider

import "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "core:time"

@(private)
g_opencode_session: string

@(private)
g_opencode_fallback: string

@(private)
g_opencode_mu: sync.Mutex

// Bind the live conversation id used for x-opencode-session.
// Chat workers override this per request via Chat_Request.session_id, so a
// background tab never carries another tab's session id.
set_session :: proc(session_id: string) {
	sync.mutex_lock(&g_opencode_mu)
	defer sync.mutex_unlock(&g_opencode_mu)
	delete(g_opencode_session)
	g_opencode_session = ""
	if len(session_id) > 0 {
		g_opencode_session = strings.clone(session_id)
	}
}

clear_session :: proc() {
	sync.mutex_lock(&g_opencode_mu)
	defer sync.mutex_unlock(&g_opencode_mu)
	delete(g_opencode_session)
	g_opencode_session = ""
	delete(g_opencode_fallback)
	g_opencode_fallback = ""
}

@(private)
opencode_affinity_id :: proc(explicit: string) -> string {
	if len(explicit) > 0 {
		return explicit
	}
	sync.mutex_lock(&g_opencode_mu)
	defer sync.mutex_unlock(&g_opencode_mu)
	if len(g_opencode_session) > 0 {
		return g_opencode_session
	}
	if len(g_opencode_fallback) == 0 {
		g_opencode_fallback = fmt.aprintf("nullray-%d-%d", os.get_pid(), time.now()._nsec)
	}
	return g_opencode_fallback
}

@(private)
is_opencode_provider :: proc(p: ^Provider) -> bool {
	if p == nil {
		return false
	}
	return p.id == "opencode" || p.id == "opencode-go"
}

@(private)
append_opencode_headers :: proc(headers: ^[dynamic]string, p: ^Provider, session_id := "") {
	if !is_opencode_provider(p) {
		return
	}
	append(headers, fmt.tprintf("x-opencode-session: %s", opencode_affinity_id(session_id)))
}
