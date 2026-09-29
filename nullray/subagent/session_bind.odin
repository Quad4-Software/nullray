// SPDX-License-Identifier: 0BSD
/*
Per-thread session binding: which session a worker's tool calls belong to.
The shared Runtime binding follows the frontmost tab, so spawns on a
background session's worker would attribute usage to the wrong file. A
thread-local bind pins each worker to its own session at job start.
*/

package subagent

import "core:strings"

@(private)
Session_Bind :: struct {
	path:    string,
	persist: bool,
	set:     bool,
}

@(thread_local)
tls_session_bind: Session_Bind

// Set the owning session for this thread. Caller clears on the way out.
session_bind_set :: proc(path: string, persist: bool) {
	delete(tls_session_bind.path)
	tls_session_bind = {}
	tls_session_bind.set = true
	tls_session_bind.persist = persist
	if len(path) > 0 {
		tls_session_bind.path = strings.clone(path)
	}
}

session_bind_clear :: proc() {
	delete(tls_session_bind.path)
	tls_session_bind = {}
}

// Returns the bound session for this thread. String is borrowed.
session_bind :: proc() -> (path: string, persist: bool, ok: bool) {
	if !tls_session_bind.set {
		return "", false, false
	}
	return tls_session_bind.path, tls_session_bind.persist, true
}
