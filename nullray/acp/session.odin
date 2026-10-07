// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
ACP session state and the prompt turn worker. ACP keeps its own
[]provider.Message per session (no disk transcript) and drives
agent.run_turn on a worker thread so session/cancel and other requests
stay responsive while a turn runs.
*/

package acp

import "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "core:thread"
import "nullray:agent"
import "nullray:constants"
import "nullray:http"
import "nullray:mcp"
import "nullray:provider"
import "nullray:session"
import "nullray:subagent"
import "nullray:tools"

Acp_Session :: struct {
	id:               string,
	cwd:              string,
	mode:             agent.Agent_Mode,
	model:            string,
	messages:         [dynamic]provider.Message,
	control_mu:       sync.Mutex,
	cancel_requested: bool,
	busy:             bool,
	worker:           ^thread.Thread,
	// Finished worker threads awaiting join at session_destroy, reaping
	// on the spot would deadlock against workers still emitting.
	retired:          [dynamic]^thread.Thread,
	owner:            ^Conn, // conn that ran session/new
	// Queued scheduled wakeups (prompt,tag owned) plus tags of wakeup
	// turns currently running, so recurring jobs stay coalesced.
	wake_mu:          sync.Mutex,
	wake_q:           [dynamic]Acp_Wakeup,
	wake_inflight:    map[string]int,
}

// Per-turn callback context shared by the event and stop-check procs.
Turn_Ctx :: struct {
	srv:          ^Server,
	sess:         ^Acp_Session,
	tool_seq:     int,
	open_tool:    int, // seq of the in-flight tool call, 0 means none
	emitted_text: bool,
	stream:       bool,
}

Prompt_Args :: struct {
	srv:         ^Server,
	sess:        ^Acp_Session,
	conn:        ^Conn,  // conn that sent session/prompt (response target)
	id_json:     string, // request id for the held-open response (owned)
	prov:        provider.Provider,
	ctx:         Turn_Ctx,
	// Scheduled wakeup turns: no JSON-RPC result exists for a synthesized
	// request, and the tag stays counted as queued until the turn ends.
	from_wakeup: bool,
	wake_tag:    string, // owned, "" for client prompts
	// Owned clone of the session model, taken under control_mu so a
	// session/set_model swap cannot free it mid-turn.
	model:       string,
}

// Serializes the ENV_MODE pin in session_rebuild_prompt, the mode env var
// is process-global and other threads may read or write it.
g_env_mu: sync.Mutex

// Build or refresh the system prompt (messages[0]) for the session mode.
// build_system_prompt reads the mode from env, so pin it for the call.
session_rebuild_prompt :: proc(srv: ^Server, s: ^Acp_Session) {
	sync.mutex_lock(&g_env_mu)
	defer sync.mutex_unlock(&g_env_mu)
	prev, had := os.lookup_env(constants.ENV_MODE, context.temp_allocator)
	prev_copy := strings.clone(prev, context.temp_allocator)
	os.set_env(constants.ENV_MODE, agent.mode_string(s.mode))
	provider_id := ""
	if p := provider.registry_active(&srv.providers); p != nil {
		provider_id = p.id
	}
	// skills loading frees file data with the heap allocator internally,
	// so a temp allocator here would corrupt the heap.
	skills_prompt := agent.load_skills_prompt()
	defer delete(skills_prompt)
	prompt := agent.build_system_prompt(skills_prompt, &srv.tools_reg, "", provider_id)
	if had {
		os.set_env(constants.ENV_MODE, prev_copy)
	} else {
		os.unset_env(constants.ENV_MODE)
	}
	if len(prompt) == 0 {
		delete(prompt)
		return
	}
	// A turn worker clones s.messages at turn start, the swap takes the
	// same lock so a mid-turn set_mode never races the clone.
	sync.mutex_lock(&s.control_mu)
	defer sync.mutex_unlock(&s.control_mu)
	if len(s.messages) == 0 {
		append(&s.messages, provider.Message{role = .System, content = prompt, cacheable = true})
	} else if s.messages[0].role == .System {
		delete(s.messages[0].content)
		s.messages[0].content = prompt
	} else {
		delete(prompt)
	}
}

session_new :: proc(srv: ^Server, id: string, cwd: string) -> ^Acp_Session {
	s := new(Acp_Session)
	s.id = strings.clone(id)
	s.cwd = strings.clone(cwd)
	s.mode = .Edit
	s.messages = make([dynamic]provider.Message)
	s.wake_q = make([dynamic]Acp_Wakeup)
	s.wake_inflight = make(map[string]int)
	session_rebuild_prompt(srv, s)
	return s
}

session_destroy :: proc(s: ^Acp_Session) {
	if s == nil {
		return
	}
	session_cancel(s)
	if s.worker != nil {
		thread.join(s.worker)
		thread.destroy(s.worker)
		s.worker = nil
	}
	for th in s.retired {
		thread.join(th)
		thread.destroy(th)
	}
	delete(s.retired)
	http.cancel_clear(rawptr(s))
	wake_clear(s)
	for m in s.messages {
		provider.destroy_message(m)
	}
	delete(s.messages)
	delete(s.id)
	delete(s.cwd)
	delete(s.model)
	free(s)
}

session_cancel :: proc(s: ^Acp_Session) {
	if s == nil {
		return
	}
	sync.mutex_lock(&s.control_mu)
	s.cancel_requested = true
	sync.mutex_unlock(&s.control_mu)
	http.cancel_request(rawptr(s))
	tools.shell_cancel_active(rawptr(s))
	if rt := subagent.runtime(); rt != nil {
		// Children spawned on this session's worker bind s.id as their
		// parent (agent_scope in prompt_worker), so cancelling s.id's
		// subtree leaves other sessions' children running on serve.
		subagent.roster_cancel_children_of(&rt.roster, s.id)
	}
}

session_clear_cancel :: proc(s: ^Acp_Session) {
	sync.mutex_lock(&s.control_mu)
	s.cancel_requested = false
	sync.mutex_unlock(&s.control_mu)
	http.cancel_clear(rawptr(s))
}

acp_stop_check :: proc(user: rawptr) -> agent.Stop_Kind {
	ctx := cast(^Turn_Ctx)user
	s := ctx.sess
	sync.mutex_lock(&s.control_mu)
	defer sync.mutex_unlock(&s.control_mu)
	if s.cancel_requested {
		return .Cancel
	}
	return .None
}

acp_event_cb :: proc(ev: agent.Event, user: rawptr) {
	ctx := cast(^Turn_Ctx)user
	srv := ctx.srv
	sid := ctx.sess.id
	switch ev.kind {
	case .Delta:
		ctx.emitted_text = true
		emit_message_chunk(srv, sid, ev.text)
	case .Reasoning_Delta:
		emit_thought_chunk(srv, sid, ev.text)
	case .Tool_Start:
		ctx.tool_seq += 1
		ctx.open_tool = ctx.tool_seq
		title := tools.tool_activity_line(ev.name, ev.text, context.temp_allocator)
		call_id := fmt.aprintf("call-%d", ctx.tool_seq, allocator = context.temp_allocator)
		emit_tool_start(srv, sid, call_id, title, ev.name)
	case .Tool_Done:
		if ctx.open_tool > 0 {
			call_id := fmt.aprintf("call-%d", ctx.open_tool, allocator = context.temp_allocator)
			emit_tool_done(srv, sid, call_id, acp_tool_failed(ev.text), ev.text)
			ctx.open_tool = 0
		}
	case .Tool_Message:
		// Tool_Done already carries the result text, skip the duplicate.
	case .Assistant_Message:
		// Non-streaming providers emit no Delta events, ship the whole
		// pre-tool assistant text here instead.
		if !ctx.stream && len(ev.text) > 0 {
			ctx.emitted_text = true
			emit_message_chunk(srv, sid, ev.text)
		}
	case .Step, .Status:
	}
}

acp_stop_reason :: proc(stopped: string, cancelled: bool) -> string {
	if cancelled || stopped == "cancelled" {
		return "cancelled"
	}
	switch stopped {
	case "max_steps":
		return "max_turn_requests"
	case:
		return "end_turn"
	}
}

// Shallow copy of the active provider plus owned clones of every string
// provider_destroy frees (base_url, api_key, default_model, caps strings).
// Without the caps clones the copy shares registry-owned strings and
// provider_destroy double-frees them. prov_mu pairs with the default_model
// swap in session/set_model so the copy never reads a freed pointer.
prompt_provider_copy :: proc(srv: ^Server, p: ^provider.Provider) -> provider.Provider {
	sync.mutex_lock(&srv.prov_mu)
	defer sync.mutex_unlock(&srv.prov_mu)
	out := p^
	out.base_url = strings.clone(p.base_url)
	out.api_key = strings.clone(p.api_key)
	out.default_model = strings.clone(p.default_model)
	out.caps.probed_model = strings.clone(p.caps.probed_model)
	out.caps.parameter_size = strings.clone(p.caps.parameter_size)
	return out
}

prompt_worker :: proc(data: rawptr) {
	args := cast(^Prompt_Args)data
	srv := args.srv
	s := args.sess
	args.ctx.srv = srv
	args.ctx.sess = s

	bind_prev := subagent.session_bind_set(s.id, false, args.model, args.prov.id)
	defer subagent.session_bind_clear(bind_prev)
	// Pin the spawn parent scope so children attribute to this session,
	// session/cancel then kills only this subtree, not every session's.
	scope_prev := subagent.agent_scope_set(s.id)
	defer subagent.agent_scope_restore(scope_prev)
	http_prev := http.bind_owner(rawptr(s))
	defer http.unbind_owner(http_prev)
	provider.set_session(s.id)

	cfg := agent.default_config()
	args.ctx.stream = cfg.stream
	// set_mode writes s.mode on the dispatch thread, read it under the
	// same lock so a mid-turn swap cannot tear the value.
	sync.mutex_lock(&s.control_mu)
	cfg.mode = s.mode
	sync.mutex_unlock(&s.control_mu)
	cfg.tools_registry = &srv.tools_reg
	cfg.on_event = acp_event_cb
	cfg.user = &args.ctx
	cfg.session_id = s.id
	cfg.stop_check = acp_stop_check
	agent.hunt_log_sampling(cfg.hunt)

	// Snapshot the transcript under the lock so a concurrent set_mode
	// prompt swap cannot free a string mid-clone.
	msgs := make([dynamic]provider.Message, 0, len(s.messages))
	sync.mutex_lock(&s.control_mu)
	for m in s.messages {
		append(&msgs, provider.clone_message(m))
	}
	sync.mutex_unlock(&s.control_mu)
	defer {
		provider.destroy_messages(msgs[:])
		delete(msgs)
	}

	req := agent.Run_Request{
		prov = &args.prov,
		messages = msgs[:],
		tools_enabled = session.tools_enabled_from_env(),
		model = args.model,
	}
	result := agent.run_turn(req, cfg)

	// Commit history. result.messages owns a full cloned transcript when
	// present, content aliases into it, so never free content separately.
	if len(result.messages) > 0 {
		sync.mutex_lock(&s.control_mu)
		provider.destroy_messages(s.messages[:])
		delete(s.messages)
		s.messages = result.messages
		sync.mutex_unlock(&s.control_mu)
	} else {
		delete(result.content)
	}

	cancelled := false
	sync.mutex_lock(&s.control_mu)
	cancelled = s.cancel_requested
	sync.mutex_unlock(&s.control_mu)

	if !args.ctx.emitted_text && len(result.content) > 0 {
		emit_message_chunk(srv, s.id, result.content)
	}

	// Wakeup turns are synthesized: there is no held-open request id, so
	// no JSON-RPC result goes out. Client prompts get their response here.
	if args.from_wakeup {
		if !result.ok && !cancelled {
			msg := result.err
			if len(msg) == 0 {
				msg = "request failed"
			}
			fmt.eprintf("nullray: scheduled wakeup turn on %s failed: %s\n", s.id, msg)
		}
	} else if !result.ok && !cancelled {
		msg := result.err
		if len(msg) == 0 {
			msg = "request failed"
		}
		send_error_conn(args.conn, args.id_json, ERR_INTERNAL, msg)
	} else {
		reason := acp_stop_reason(result.stopped, cancelled)
		b: strings.Builder
		strings.builder_init(&b, context.temp_allocator)
		strings.write_string(&b, `{"stopReason":`)
		mcp.write_json_string(&b, reason)
		strings.write_byte(&b, '}')
		send_result_conn(args.conn, args.id_json, strings.to_string(b))
	}

	// Clear busy LAST, after every emit and cleanup above. Clearing it
	// earlier lets a second prompt spawn a worker while this one is still
	// writing updates, which orphans s.worker and leaks the thread.
	sync.mutex_lock(&s.control_mu)
	if len(args.wake_tag) > 0 {
		wake_done(s, args.wake_tag)
	}
	s.busy = false
	sync.mutex_unlock(&s.control_mu)

	delete(result.err)
	delete(result.stopped)
	provider.provider_destroy(&args.prov)
	delete(args.id_json)
	delete(args.wake_tag)
	delete(args.model)
	free(args)
}
