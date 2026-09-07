// SPDX-License-Identifier: 0BSD
/*
OpenCode Zen and Go request headers for routing and session affinity.
*/

package provider

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

@(private)
g_opencode_session: string

@(private)
g_opencode_fallback: string

// Bind the live conversation id used for x-opencode-session.
set_session :: proc(session_id: string) {
	delete(g_opencode_session)
	g_opencode_session = ""
	if len(session_id) > 0 {
		g_opencode_session = strings.clone(session_id)
	}
}

clear_session :: proc() {
	delete(g_opencode_session)
	g_opencode_session = ""
	delete(g_opencode_fallback)
	g_opencode_fallback = ""
}

@(private)
opencode_affinity_id :: proc() -> string {
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
append_opencode_headers :: proc(headers: ^[dynamic]string, p: ^Provider) {
	if !is_opencode_provider(p) {
		return
	}
	append(headers, fmt.tprintf("x-opencode-session: %s", opencode_affinity_id()))
}
