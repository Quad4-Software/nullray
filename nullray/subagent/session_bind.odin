// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
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
	path:        string,
	persist:     bool,
	set:         bool,
	model:       string,
	provider_id: string,
}

@(thread_local)
tls_session_bind: Session_Bind

// Set the owning session for this thread and return the previous binding so
// the caller can restore it. Synchronous child jobs run on the parent thread,
// where a plain clear would leave the rest of the parent turn unbound.
session_bind_set :: proc(path: string, persist: bool, model := "", provider_id := "") -> (prev: Session_Bind) {
	prev = tls_session_bind
	tls_session_bind = {}
	tls_session_bind.set = true
	tls_session_bind.persist = persist
	if len(path) > 0 {
		tls_session_bind.path = strings.clone(path)
	}
	if len(model) > 0 {
		tls_session_bind.model = strings.clone(model)
	}
	if len(provider_id) > 0 {
		tls_session_bind.provider_id = strings.clone(provider_id)
	}
	return prev
}

session_bind_clear :: proc(prev: Session_Bind) {
	delete(tls_session_bind.path)
	delete(tls_session_bind.model)
	delete(tls_session_bind.provider_id)
	tls_session_bind = prev
}

// Active model and provider for this thread's session. Borrowed strings,
// empty when unbound or when the caller did not pin identity.
session_bind_identity :: proc() -> (model: string, provider_id: string, ok: bool) {
	if !tls_session_bind.set {
		return "", "", false
	}
	return tls_session_bind.model, tls_session_bind.provider_id, true
}

// Returns the bound session for this thread. String is borrowed.
session_bind :: proc() -> (path: string, persist: bool, ok: bool) {
	if !tls_session_bind.set {
		return "", false, false
	}
	return tls_session_bind.path, tls_session_bind.persist, true
}

// Per-thread parent-agent override. rt.current_agent is a single shared
// value, so on a multi-session host (serve) concurrent session workers
// would clobber it for each other, a thread-local scope pins the parent id
// a worker's spawns attribute to without touching the shared field.
@(thread_local)
tls_agent_scope: string

// Set this thread's spawn parent scope, returns the previous value so the
// caller can restore it. Owned internally.
agent_scope_set :: proc(id: string) -> (prev: string) {
	prev = tls_agent_scope
	tls_agent_scope = ""
	if len(id) > 0 {
		tls_agent_scope = strings.clone(id)
	}
	return prev
}

agent_scope_restore :: proc(prev: string) {
	delete(tls_agent_scope)
	tls_agent_scope = prev
}

// Borrowed, "" when no scope is bound on this thread.
agent_scope :: proc() -> string {
	return tls_agent_scope
}
