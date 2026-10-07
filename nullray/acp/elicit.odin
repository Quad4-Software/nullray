// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
elicitation/create bridge. When the client advertises
capabilities.elicitation.form, tools that block on ask.request (the
ask_question and ask_secret tools) are answered through an ACP form
elicit instead of failing. The responder runs on the blocked worker
thread, the dispatch thread fulfills the wait when the response lands.
*/

package acp

import "core:encoding/json"
import "core:strings"
import "core:sync"
import "core:time"
import "nullray:ask"
import "nullray:http"
import "nullray:mcp"

elicit_install :: proc(srv: ^Server) {
	if srv == nil || !srv.cap_elicit_form {
		return
	}
	ask.set_responder(acp_ask_responder, srv)
}

elicit_uninstall :: proc() {
	ask.set_responder(nil, nil)
}

@(private)
build_elicit_params :: proc(session_id, prompt: string, options: []string) -> string {
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	strings.write_string(&b, `{"sessionId":`)
	mcp.write_json_string(&b, session_id)
	strings.write_string(&b, `,"mode":"form","message":`)
	mcp.write_json_string(&b, prompt)
	strings.write_string(&b, `,"requestedSchema":{"type":"object","properties":{"answer":{"type":"string"`)
	if len(options) > 0 {
		strings.write_string(&b, `,"enum":[`)
		for o, i in options {
			if i > 0 {
				strings.write_byte(&b, ',')
			}
			mcp.write_json_string(&b, o)
		}
		strings.write_byte(&b, ']')
	}
	strings.write_string(&b, `}},"required":["answer"]}}`)
	return strings.to_string(b)
}

acp_ask_responder :: proc(
	kind: ask.Kind,
	prompt: string,
	options: []string,
	user: rawptr,
	allocator := context.allocator,
) -> (
	answer: string,
	ok: bool,
	cancelled: bool,
) {
	srv := cast(^Server)user
	if srv == nil || !srv.cap_elicit_form {
		return "", false, false
	}
	sess := cast(^Acp_Session)http.owner_for_thread()
	sid := ""
	conn: ^Conn
	if sess != nil {
		sid = sess.id
		conn = sess.owner
	}
	if conn == nil {
		conn = srv.stdin_conn
	}
	// On serve, only a conn that advertised elicitation.form can answer.
	if conn == nil || !conn.elicit_form {
		return "", false, false
	}
	opts := options
	if kind == .Confirm && len(opts) == 0 {
		opts = []string{"yes", "no"}
	}
	params := build_elicit_params(sid, prompt, opts)

	id := next_outbound_id(srv)
	w := new(Outbound_Wait)
	sync.mutex_lock(&srv.pending_mu)
	srv.pending_out[id] = w
	sync.mutex_unlock(&srv.pending_mu)
	send_request_conn(conn, id, "elicitation/create", params)

	sync.mutex_lock(&w.mu)
	for !w.done {
		_ = sync.cond_wait_with_timeout(&w.cond, &w.mu, 200 * time.Millisecond)
		if w.done {
			break
		}
		if sess != nil {
			sync.mutex_lock(&sess.control_mu)
			if sess.cancel_requested {
				sync.mutex_unlock(&sess.control_mu)
				break
			}
			sync.mutex_unlock(&sess.control_mu)
		}
		sync.mutex_lock(&srv.in_mu)
		done_io := srv.eof || srv.stop
		sync.mutex_unlock(&srv.in_mu)
		if done_io {
			break
		}
	}
	sync.mutex_unlock(&w.mu)

	sync.mutex_lock(&srv.pending_mu)
	delete_key(&srv.pending_out, id)
	sync.mutex_unlock(&srv.pending_mu)

	defer wait_destroy(w)
	if !w.done {
		return "", false, true
	}
	if len(w.err) > 0 {
		return "", false, false
	}
	if w.action == "accept" {
		return strings.clone(w.answer, allocator), true, false
	}
	// decline and cancel both mean the user did not provide an answer.
	return "", false, true
}

// Called on the dispatch thread when an inbound message is a response
// (has id, no method) to an outbound request. result_obj may be empty.
// pending_mu stays held across the w.mu write: the responder only removes
// the wait from pending_out under pending_mu, so holding it here keeps w
// alive while we mark it (first response wins, later ones are dropped).
elicit_handle_response :: proc(srv: ^Server, id: int, result: json.Object, err_text: string) {
	sync.mutex_lock(&srv.pending_mu)
	defer sync.mutex_unlock(&srv.pending_mu)
	w, found := srv.pending_out[id]
	if !found || w == nil {
		return
	}
	sync.mutex_lock(&w.mu)
	defer sync.mutex_unlock(&w.mu)
	if w.done {
		return
	}
	w.done = true
	if len(err_text) > 0 {
		w.err = strings.clone(err_text)
	} else {
		action, _ := jobj_str(result, "action")
		w.action = strings.clone(action)
		if content, ok := result["content"].(json.Object); ok {
			if ans, aok := jobj_str(content, "answer"); aok {
				w.answer = strings.clone(ans)
			}
		}
	}
	sync.cond_signal(&w.cond)
}
