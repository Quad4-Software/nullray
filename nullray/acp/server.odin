// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
ACP server: registry setup, inbound dispatch, and the client -> agent
method handlers.
*/

package acp

import "core:encoding/json"
import "core:fmt"
import "core:strings"
import "core:sync"
import "core:thread"
import "nullray:agent"
import "nullray:constants"
import "nullray:mcp"
import "nullray:provider"
import "nullray:rag"
import "nullray:schedule"
import "nullray:subagent"
import "nullray:tools"

// Build the shared runtime: tool, mcp, and provider registries plus the
// subagent runtime. Used by both transports (--acp stdio and serve).
// Pair with server_runtime_destroy.
server_runtime_init :: proc(srv: ^Server, bare: bool) {
	srv.bare = bare
	srv.inbox = make([dynamic]Inbound)
	srv.sessions = make(map[string]^Acp_Session)
	srv.pending_out = make(map[int]^Outbound_Wait)
	srv.conns = make(map[int]^Conn)

	tools.registry_init(&srv.tools_reg)
	mcp.registry_init(&srv.mcp_reg, &srv.tools_reg)
	if !bare && !agent.bare_from_env() {
		mcp.mcp_autoload(&srv.mcp_reg)
	}
	provider.registry_init(&srv.providers)
	rag.install_memory_hooks()
	rag.bind_providers(&srv.providers, provider.registry_active(&srv.providers))

	subagent.runtime_init(&srv.rt, "acp", &srv.tools_reg)
	subagent.runtime_set_session(&srv.rt, "", false)
	subagent.runtime_set(&srv.rt)
	agent.register_subagent_runner()
	if p := provider.registry_active(&srv.providers); p != nil {
		subagent.runtime_set_provider(&srv.rt, p)
		delete(srv.rt.main_model)
		srv.rt.main_model = strings.clone(p.default_model)
	}
	tools.register_subagent_tools(&srv.tools_reg, subagent.runtime_enabled(&srv.rt))
}

server_runtime_destroy :: proc(srv: ^Server) {
	subagent.runtime_set(nil)
	subagent.runtime_destroy(&srv.rt)
	provider.registry_destroy(&srv.providers)
	mcp.registry_destroy(&srv.mcp_reg)
	tools.registry_destroy(&srv.tools_reg)
}

// After the dispatch loop exits: stop the wakeup pump, destroy sessions,
// fail pending elicitation waiters, drop conns, and uninstall the ask
// responder.
server_teardown :: proc(srv: ^Server) {
	// The pump iterates srv.sessions; join it before sessions are freed.
	if srv.wake_pump != nil {
		thread.join(srv.wake_pump)
		thread.destroy(srv.wake_pump)
		srv.wake_pump = nil
	}
	// Collect session pointers under the lock, then destroy them outside
	// it: session_destroy joins a worker whose emit path takes
	// sessions_mu via notify_targets, so destroying under the lock
	// deadlocks on SIGTERM during a live turn.
	dead := make([dynamic]^Acp_Session, 0, len(srv.sessions), context.temp_allocator)
	sync.mutex_lock(&srv.sessions_mu)
	for _, s in srv.sessions {
		append(&dead, s)
	}
	clear(&srv.sessions)
	srv.wake_fallback = nil
	sync.mutex_unlock(&srv.sessions_mu)
	// Flag cancellation on every session first so workers wind down
	// before any blocking join runs.
	for s in dead {
		session_cancel(s)
	}
	for s in dead {
		session_destroy(s)
	}
	sync.mutex_lock(&srv.pending_mu)
	waits := make([dynamic]^Outbound_Wait, 0, len(srv.pending_out), context.temp_allocator)
	for _, w in srv.pending_out {
		append(&waits, w)
	}
	clear(&srv.pending_out)
	sync.mutex_unlock(&srv.pending_mu)
	for w in waits {
		sync.mutex_lock(&w.mu)
		w.done = true
		w.err = strings.clone("transport closed")
		sync.cond_signal(&w.cond)
		sync.mutex_unlock(&w.mu)
	}
	elicit_uninstall()
	conns_destroy(srv)
	delete(srv.inbox)
}

run_server :: proc(bare := false) -> int {
	srv := new(Server)
	server_runtime_init(srv, bare)
	defer server_runtime_destroy(srv)

	// Scheduled jobs fire into sessions through the scoped wakeup sink;
	// NULLRAY_SCHEDULE=0 disables the watcher entirely.
	sched_on := false
	if schedule.schedule_enabled() {
		schedule.schedule_init()
		schedule_bind(srv)
		schedule.schedule_start()
		sched_on = true
	}

	srv.stdin_conn = conn_new(srv, -1)
	srv.reader = thread.create_and_start_with_data(srv, reader_main, nil, .Normal, false)
	if srv.reader == nil {
		fmt.eprintln("nullray: acp: failed to start stdin reader")
		return 1
	}

	dispatch_loop(srv)

	// Stop the watcher before teardown so a late emit cannot hit a
	// session mid-destroy, then shut down sessions and waiters.
	if sched_on {
		schedule.schedule_stop()
	}
	server_teardown(srv)
	return 0
}

dispatch_loop :: proc(srv: ^Server) {
	for {
		msg, ok := pop_inbound(srv)
		if !ok {
			return
		}
		srv.dispatch_conn = msg.conn
		dispatch_line(srv, msg.line)
		delete(msg.line)
		// Per-message arena reset keeps the parsed JSON tree transient.
		free_all(context.temp_allocator)
	}
}

dispatch_line :: proc(srv: ^Server, line: string) {
	trimmed := strings.trim_space(line)
	if len(trimmed) == 0 {
		return
	}
	doc, perr := json.parse_string(trimmed, .JSON, allocator = context.temp_allocator)
	if perr != .None {
		send_error(srv, "", ERR_PARSE, "parse error")
		return
	}
	obj, is_obj := doc.(json.Object)
	if !is_obj {
		send_error(srv, "", ERR_INVALID, "invalid request")
		return
	}
	id_json, has_id := envelope_id(obj)
	method, has_method := jobj_str(obj, "method")

	if !has_method {
		// Client response to an outbound request (elicitation/create).
		if has_id {
			handle_client_response(srv, obj, id_json)
		}
		return
	}
	if !has_id {
		dispatch_notification(srv, method, params_obj(obj))
		return
	}

	switch method {
	case "initialize":
		handle_initialize(srv, id_json, params_obj(obj))
	case "authenticate":
		send_result(srv, id_json, "{}")
	case "session/new":
		handle_session_new(srv, id_json, params_obj(obj))
	case "session/prompt":
		handle_session_prompt(srv, id_json, params_obj(obj))
	case "session/set_mode":
		handle_set_mode(srv, id_json, params_obj(obj))
	case "session/set_model":
		handle_set_model(srv, id_json, params_obj(obj))
	case "session/list":
		handle_session_list(srv, id_json)
	case "session/subscribe":
		handle_session_subscribe(srv, id_json, params_obj(obj))
	case "session/close", "session/delete":
		handle_session_close(srv, id_json, params_obj(obj))
	case:
		send_error(srv, id_json, ERR_NOT_FOUND, fmt.tprintf("method not found: %s", method))
	}
}

dispatch_notification :: proc(srv: ^Server, method: string, params: json.Object) {
	switch method {
	case "session/cancel":
		if sid, ok := jobj_str(params, "sessionId"); ok {
			session_cancel(find_session(srv, sid))
		}
	case:
		// Unknown notifications are ignored per JSON-RPC.
	}
}

handle_client_response :: proc(srv: ^Server, obj: json.Object, id_json: string) {
	id, is_int := json_id_int(obj)
	if !is_int {
		return
	}
	err_text := ""
	if err_v, ok := obj["error"].(json.Object); ok {
		err_text, _ = jobj_str(err_v, "message")
		if len(err_text) == 0 {
			err_text = "request failed"
		}
	}
	result, _ := obj["result"].(json.Object)
	elicit_handle_response(srv, id, result, err_text)
}

// --- params helpers -----------------------------------------------------

params_obj :: proc(obj: json.Object) -> json.Object {
	p, _ := obj["params"].(json.Object)
	return p
}

jobj_str :: proc(obj: json.Object, key: string) -> (string, bool) {
	v, ok := obj[key]
	if !ok {
		return "", false
	}
	s, is_s := v.(json.String)
	if !is_s {
		return "", false
	}
	return string(s), true
}

jobj_int :: proc(obj: json.Object, key: string) -> (i64, bool) {
	v, ok := obj[key]
	if !ok {
		return 0, false
	}
	#partial switch n in v {
	case json.Integer:
		return i64(n), true
	case json.Float:
		return i64(n), true
	}
	return 0, false
}

// Raw serialized id, so string ids echo back quoted and ints bare.
envelope_id :: proc(obj: json.Object) -> (raw: string, has: bool) {
	v, ok := obj["id"]
	if !ok {
		return "", false
	}
	#partial switch id in v {
	case json.Integer:
		return fmt.tprintf("%d", i64(id)), true
	case json.Float:
		return fmt.tprintf("%d", i64(id)), true
	case json.String:
		b: strings.Builder
		strings.builder_init(&b, context.temp_allocator)
		mcp.write_json_string(&b, string(id))
		return strings.to_string(b), true
	case json.Null:
		return "", false
	}
	return "", false
}

json_id_int :: proc(obj: json.Object) -> (int, bool) {
	v, ok := obj["id"]
	if !ok {
		return 0, false
	}
	#partial switch id in v {
	case json.Integer:
		return int(id), true
	case json.Float:
		return int(id), true
	}
	return 0, false
}
