// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Agent Client Protocol (ACP) v1 server. nullray --acp speaks
newline-delimited JSON-RPC 2.0 over stdio so editors (Zed and peers)
can drive the agent. stdout carries only protocol messages; logs go to
stderr.
*/

package acp

import "core:sync"
import "core:thread"
import "nullray:mcp"
import "nullray:provider"
import "nullray:subagent"
import "nullray:tools"

PROTOCOL_VERSION :: 1

ERR_PARSE :: -32700
ERR_INVALID :: -32600
ERR_NOT_FOUND :: -32601
ERR_PARAMS :: -32602
ERR_INTERNAL :: -32603
ERR_CANCELLED :: -32800

// One inbound line from a client conn. line is an owned heap copy that the
// dispatch loop frees after handling.
Inbound :: struct {
	line: string,
	conn: ^Conn,
}

// One client transport connection. fd < 0 means the stdio transport
// (conn 0 in --acp mode, writes go to stdout). Socket conns get a line
// reader thread each; subs holds the session ids this conn receives
// session/update notifications for.
Conn :: struct {
	srv:         ^Server,
	id:          int,
	fd:          int,
	mu:          sync.Mutex,
	closed:      bool,
	subs:        map[string]bool,
	elicit_form: bool,
}

// Tracks one agent -> client request (elicitation/create) until the
// client response lands on the dispatch thread.
Outbound_Wait :: struct {
	mu:     sync.Mutex,
	cond:   sync.Cond,
	done:   bool,
	action: string, // accept | decline | cancel (owned)
	answer: string, // content.answer when the form is accepted (owned)
	err:    string, // owned
}

Server :: struct {
	out_mu:  sync.Mutex,
	in_mu:   sync.Mutex,
	in_cond: sync.Cond,
	inbox:   [dynamic]Inbound,
	eof:     bool,

	sessions:    map[string]^Acp_Session,
	sessions_mu: sync.Mutex,
	session_seq: int,

	pending_mu:  sync.Mutex,
	next_out_id: int,
	pending_out: map[int]^Outbound_Wait,

	cap_fs_read:     bool,
	cap_fs_write:    bool,
	cap_terminal:    bool,
	cap_elicit_form: bool,
	cap_elicit_url:  bool,

	// Transport conns. stdin is conn 0 in --acp mode; the socket daemon
	// (nullray serve) registers one conn per accepted client.
	conns:         map[int]^Conn,
	conns_mu:      sync.Mutex,
	next_conn:     int,
	dispatch_conn: ^Conn, // conn currently being served on the dispatch thread
	stdin_conn:    ^Conn,
	stop:          bool,  // serve shutdown: drained inbox then dispatch exits

	// Scheduled wakeup delivery (serve daemon). wake_fallback is the most
	// recently prompted session, used for jobs with no session_scope.
	// Guarded by sessions_mu.
	wake_fallback: ^Acp_Session,
	wake_pump:     ^thread.Thread,

	// Serializes provider field reads (worker-side snapshot copies) with
	// the default_model swap in session/set_model on the dispatch thread.
	prov_mu: sync.Mutex,

	tools_reg: tools.Registry,
	mcp_reg:   mcp.Registry,
	providers: provider.Registry,
	rt:        subagent.Runtime,

	reader: ^thread.Thread,
	bare:   bool,
}

push_inbound :: proc(srv: ^Server, msg: Inbound) {
	sync.mutex_lock(&srv.in_mu)
	defer sync.mutex_unlock(&srv.in_mu)
	append(&srv.inbox, msg)
	sync.cond_signal(&srv.in_cond)
}

pop_inbound :: proc(srv: ^Server) -> (Inbound, bool) {
	for {
		sync.mutex_lock(&srv.in_mu)
		if len(srv.inbox) > 0 {
			m := srv.inbox[0]
			ordered_remove(&srv.inbox, 0)
			sync.mutex_unlock(&srv.in_mu)
			return m, true
		}
		if srv.eof || srv.stop {
			sync.mutex_unlock(&srv.in_mu)
			return {}, false
		}
		sync.cond_wait(&srv.in_cond, &srv.in_mu)
		sync.mutex_unlock(&srv.in_mu)
	}
}

find_session :: proc(srv: ^Server, id: string) -> ^Acp_Session {
	sync.mutex_lock(&srv.sessions_mu)
	defer sync.mutex_unlock(&srv.sessions_mu)
	return srv.sessions[id]
}

next_outbound_id :: proc(srv: ^Server) -> int {
	sync.mutex_lock(&srv.pending_mu)
	defer sync.mutex_unlock(&srv.pending_mu)
	srv.next_out_id += 1
	return srv.next_out_id
}

wait_destroy :: proc(w: ^Outbound_Wait) {
	if w == nil {
		return
	}
	delete(w.action)
	delete(w.answer)
	delete(w.err)
	free(w)
}
