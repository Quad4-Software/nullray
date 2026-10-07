// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Client -> agent method handlers: initialize, session lifecycle, prompt,
mode and model switching.
*/

package acp

import "core:encoding/json"
import "core:fmt"
import "core:strings"
import "core:sync"
import "core:thread"
import "nullray:agent"
import "nullray:constants"
import "nullray:hooks"
import "nullray:mcp"
import "nullray:provider"
import "nullray:subagent"

handle_initialize :: proc(srv: ^Server, id_json: string, params: json.Object) {
	client_version := PROTOCOL_VERSION
	if v, ok := jobj_int(params, "protocolVersion"); ok && v > 0 {
		client_version = int(v)
	}
	negotiated := client_version
	if negotiated > PROTOCOL_VERSION {
		negotiated = PROTOCOL_VERSION
	}

	// Client capabilities. All reads tolerate a missing subtree.
	if caps, ok := params["clientCapabilities"].(json.Object); ok {
		if fs, ok := caps["fs"].(json.Object); ok {
			_, srv.cap_fs_read = fs["readTextFile"]
			_, srv.cap_fs_write = fs["writeTextFile"]
		}
		if t, ok := caps["terminal"]; ok {
			if b, is_b := t.(bool); is_b {
				srv.cap_terminal = b
			}
		}
		if el, ok := caps["elicitation"].(json.Object); ok {
			_, srv.cap_elicit_form = el["form"]
			_, srv.cap_elicit_url = el["url"]
		}
	}
	if srv.dispatch_conn != nil {
		srv.dispatch_conn.elicit_form = srv.cap_elicit_form
	}
	elicit_install(srv)

	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	strings.write_string(&b, `{"protocolVersion":`)
	fmt.sbprint(&b, negotiated)
	strings.write_string(&b, `,"agentCapabilities":{`)
	strings.write_string(&b, `"loadSession":false,`)
	strings.write_string(&b, `"promptCapabilities":{"image":false,"audio":false,"embeddedContext":false},`)
	strings.write_string(&b, `"mcpCapabilities":{"http":false,"sse":false}`)
	strings.write_string(&b, `},"authMethods":[],"agentInfo":{"name":`)
	mcp.write_json_string(&b, constants.APP_NAME)
	strings.write_string(&b, `,"version":`)
	mcp.write_json_string(&b, constants.VERSION)
	strings.write_string(&b, `}}`)
	send_result(srv, id_json, strings.to_string(b))
}

MODES_JSON :: `"modes":{"currentModeId":"edit","availableModes":[` +
	`{"id":"ask","name":"Ask","description":"Read-only questions about the code"},` +
	`{"id":"plan","name":"Plan","description":"Propose an approach without edits"},` +
	`{"id":"review","name":"Review","description":"Review code or diffs for defects"},` +
	`{"id":"edit","name":"Edit","description":"Full read, write, and shell access"},` +
	`{"id":"orchestrate","name":"Orchestrate","description":"Coordinate subagents"}]}`

handle_session_new :: proc(srv: ^Server, id_json: string, params: json.Object) {
	cwd, _ := jobj_str(params, "cwd")
	srv.session_seq += 1
	id := fmt.aprintf("acp-%d", srv.session_seq)
	s := session_new(srv, id, cwd)
	s.owner = srv.dispatch_conn
	sync.mutex_lock(&srv.sessions_mu)
	srv.sessions[s.id] = s
	sync.mutex_unlock(&srv.sessions_mu)

	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	strings.write_string(&b, `{"sessionId":`)
	mcp.write_json_string(&b, id)
	strings.write_byte(&b, ',')
	strings.write_string(&b, MODES_JSON)
	strings.write_byte(&b, '}')
	send_result(srv, id_json, strings.to_string(b))
	delete(id)
}

handle_session_list :: proc(srv: ^Server, id_json: string) {
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	strings.write_string(&b, `{"sessions":[`)
	sync.mutex_lock(&srv.sessions_mu)
	first := true
	for _, s in srv.sessions {
		if !first {
			strings.write_byte(&b, ',')
		}
		first = false
		strings.write_string(&b, `{"sessionId":`)
		mcp.write_json_string(&b, s.id)
		strings.write_string(&b, `,"cwd":`)
		mcp.write_json_string(&b, s.cwd)
		strings.write_byte(&b, '}')
	}
	sync.mutex_unlock(&srv.sessions_mu)
	strings.write_string(&b, `]}`)
	send_result(srv, id_json, strings.to_string(b))
}

handle_session_close :: proc(srv: ^Server, id_json: string, params: json.Object) {
	sid, ok := jobj_str(params, "sessionId")
	if !ok {
		send_error(srv, id_json, ERR_PARAMS, "sessionId required")
		return
	}
	sync.mutex_lock(&srv.sessions_mu)
	s, found := srv.sessions[sid]
	if found {
		delete_key(&srv.sessions, sid)
		if srv.wake_fallback == s {
			srv.wake_fallback = nil
		}
	}
	sync.mutex_unlock(&srv.sessions_mu)
	if !found {
		send_error(srv, id_json, ERR_PARAMS, "unknown session")
		return
	}
	// Joins a running turn worker before freeing the session struct.
	session_destroy(s)
	send_result(srv, id_json, "{}")
}

// nullray serve extension: mark the calling conn as a subscriber for
// sessionId so session/update notifications reach attach clients that
// did not create the session.
handle_session_subscribe :: proc(srv: ^Server, id_json: string, params: json.Object) {
	sid, ok := jobj_str(params, "sessionId")
	if !ok {
		send_error(srv, id_json, ERR_PARAMS, "sessionId required")
		return
	}
	if find_session(srv, sid) == nil {
		send_error(srv, id_json, ERR_PARAMS, "unknown session")
		return
	}
	if srv.dispatch_conn != nil {
		conn_subscribe(srv, srv.dispatch_conn, sid)
	}
	send_result(srv, id_json, "{}")
}

// Concatenate text blocks, fold resource links into text lines, and skip
// image or audio blocks (not advertised in promptCapabilities).
prompt_text :: proc(params: json.Object, allocator := context.allocator) -> (string, bool) {
	blocks, ok := params["prompt"].(json.Array)
	if !ok || len(blocks) == 0 {
		return "", false
	}
	b: strings.Builder
	strings.builder_init(&b, allocator)
	for bv in blocks {
		block, is_obj := bv.(json.Object)
		if !is_obj {
			continue
		}
		kind, _ := jobj_str(block, "type")
		switch kind {
		case "text":
			if t, ok := jobj_str(block, "text"); ok {
				if strings.builder_len(b) > 0 {
					strings.write_byte(&b, '\n')
				}
				strings.write_string(&b, t)
			}
		case "resource_link":
			uri, _ := jobj_str(block, "uri")
			name, _ := jobj_str(block, "name")
			if len(uri) > 0 {
				if strings.builder_len(b) > 0 {
					strings.write_byte(&b, '\n')
				}
				if len(name) > 0 {
					strings.write_string(&b, name)
					strings.write_string(&b, " ")
				}
				strings.write_string(&b, uri)
			}
		case "resource":
			if res, ok := block["resource"].(json.Object); ok {
				t, _ := jobj_str(res, "text")
				if len(t) == 0 {
					t, _ = jobj_str(res, "uri")
				}
				if len(t) > 0 {
					if strings.builder_len(b) > 0 {
						strings.write_byte(&b, '\n')
					}
					strings.write_string(&b, t)
				}
			}
		case:
			// image, audio, and unknown blocks are dropped.
		}
	}
	text := strings.trim_space(strings.to_string(b))
	if len(text) == 0 {
		delete(strings.to_string(b))
		return "", false
	}
	return strings.clone(text, allocator), true
}

handle_session_prompt :: proc(srv: ^Server, id_json: string, params: json.Object) {
	sid, ok := jobj_str(params, "sessionId")
	if !ok {
		send_error(srv, id_json, ERR_PARAMS, "sessionId required")
		return
	}
	s := find_session(srv, sid)
	if s == nil {
		send_error(srv, id_json, ERR_PARAMS, "unknown session")
		return
	}
	text, has_text := prompt_text(params, context.temp_allocator)
	if !has_text {
		send_error(srv, id_json, ERR_PARAMS, "prompt has no text content")
		return
	}
	p := provider.registry_active(&srv.providers)
	if p == nil || p.chat == nil {
		send_error(srv, id_json, ERR_INTERNAL, "no provider")
		return
	}

	// UserPromptSubmit hook parity with the TUI and --print paths: a
	// blocking hook (exit 2) refuses the prompt before it enters history.
	prompt_hook := hooks.run(.UserPromptSubmit, "", text, context.temp_allocator)
	if prompt_hook.blocked {
		msg := prompt_hook.message
		if len(msg) == 0 {
			msg = "prompt blocked by UserPromptSubmit hook"
		}
		err_msg := strings.clone(msg, context.temp_allocator)
		hooks.result_destroy(&prompt_hook, context.temp_allocator)
		send_error(srv, id_json, ERR_INTERNAL, err_msg)
		return
	}
	hooks.result_destroy(&prompt_hook, context.temp_allocator)

	sync.mutex_lock(&s.control_mu)
	if s.busy {
		sync.mutex_unlock(&s.control_mu)
		send_error(srv, id_json, ERR_INTERNAL, "session prompt already in progress")
		return
	}
	s.busy = true
	s.cancel_requested = false
	model_copy := strings.clone(s.model)
	// The previous worker sets busy=false only after its last emit, so it
	// is done touching the session but may not have exited yet. Park the
	// handle for session_destroy instead of overwriting or joining here.
	if s.worker != nil {
		append(&s.retired, s.worker)
		s.worker = nil
	}
	sync.mutex_unlock(&s.control_mu)
	// Clear the http cancel owner flag too, a stale one makes the next
	// turn fail instantly with "cancelled" after a session/cancel.
	session_clear_cancel(s)

	// Newest prompted session is the wakeup target for scopeless jobs.
	sync.mutex_lock(&srv.sessions_mu)
	srv.wake_fallback = s
	sync.mutex_unlock(&srv.sessions_mu)

	// A conn prompting a session it does not own still sees the turn's
	// updates for that turn (subscriptions persist for the conn's life).
	if srv.dispatch_conn != nil && s.owner != srv.dispatch_conn {
		conn_subscribe(srv, srv.dispatch_conn, sid)
	}

	append(&s.messages, provider.Message{role = .User, content = strings.clone(text)})

	args := new(Prompt_Args)
	args.srv = srv
	args.sess = s
	args.conn = srv.dispatch_conn
	args.id_json = strings.clone(id_json)
	args.model = model_copy
	args.prov = prompt_provider_copy(srv, p)

	th := thread.create_and_start_with_data(args, prompt_worker, nil, .Normal, false)
	if th == nil {
		sync.mutex_lock(&s.control_mu)
		s.busy = false
		sync.mutex_unlock(&s.control_mu)
		provider.provider_destroy(&args.prov)
		delete(args.id_json)
		delete(args.model)
		free(args)
		send_error(srv, id_json, ERR_INTERNAL, "failed to start prompt worker")
		return
	}
	sync.mutex_lock(&s.control_mu)
	s.worker = th
	sync.mutex_unlock(&s.control_mu)
	// The worker sends the session/prompt response when the turn ends.
}

handle_set_mode :: proc(srv: ^Server, id_json: string, params: json.Object) {
	sid, ok := jobj_str(params, "sessionId")
	if !ok {
		send_error(srv, id_json, ERR_PARAMS, "sessionId required")
		return
	}
	mode_id, ok2 := jobj_str(params, "modeId")
	if !ok2 {
		send_error(srv, id_json, ERR_PARAMS, "modeId required")
		return
	}
	mode, found := agent.mode_from_string(mode_id)
	if !found {
		send_error(srv, id_json, ERR_PARAMS, fmt.tprintf("unknown mode: %s", mode_id))
		return
	}
	s := find_session(srv, sid)
	if s == nil {
		send_error(srv, id_json, ERR_PARAMS, "unknown session")
		return
	}
	// Workers read s.mode under control_mu at turn start.
	sync.mutex_lock(&s.control_mu)
	s.mode = mode
	sync.mutex_unlock(&s.control_mu)
	session_rebuild_prompt(srv, s)
	emit_mode_update(srv, sid, agent.mode_string(mode))
	send_result(srv, id_json, "{}")
}

handle_set_model :: proc(srv: ^Server, id_json: string, params: json.Object) {
	sid, ok := jobj_str(params, "sessionId")
	if !ok {
		send_error(srv, id_json, ERR_PARAMS, "sessionId required")
		return
	}
	model_id, ok2 := jobj_str(params, "modelId")
	if !ok2 || len(strings.trim_space(model_id)) == 0 {
		send_error(srv, id_json, ERR_PARAMS, "modelId required")
		return
	}
	s := find_session(srv, sid)
	if s == nil {
		send_error(srv, id_json, ERR_PARAMS, "unknown session")
		return
	}
	p := provider.registry_active(&srv.providers)
	resolved, rerr := subagent.policy_resolve(
		"main",
		model_id,
		p != nil ? p.default_model : "",
		srv.rt.main_model,
		context.temp_allocator,
	)
	if len(rerr) > 0 {
		send_error(srv, id_json, ERR_PARAMS, rerr)
		return
	}
	// s.model is cloned for workers under control_mu, p.default_model is
	// read by provider snapshots under prov_mu.
	sync.mutex_lock(&s.control_mu)
	delete(s.model)
	s.model = strings.clone(resolved)
	sync.mutex_unlock(&s.control_mu)
	if p != nil {
		sync.mutex_lock(&srv.prov_mu)
		delete(p.default_model)
		p.default_model = strings.clone(resolved)
		sync.mutex_unlock(&srv.prov_mu)
	}
	delete(srv.rt.main_model)
	srv.rt.main_model = strings.clone(resolved)

	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	strings.write_string(&b, `{"modelId":`)
	mcp.write_json_string(&b, resolved)
	strings.write_byte(&b, '}')
	send_result(srv, id_json, strings.to_string(b))
}
