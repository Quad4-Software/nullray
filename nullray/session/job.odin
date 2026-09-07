// SPDX-License-Identifier: 0BSD
/*
Background chat job, turn commit, cancel/pause/resume.
*/

package session

import "core:fmt"
import "core:strings"
import "core:sync"
import "core:thread"
import "nullray:agent"
import "nullray:http"
import "nullray:provider"
import "nullray:sandbox"
import "nullray:store"
import "nullray:subagent"
import "nullray:tools"

Job_Args :: struct {
	session:           ^Session,
	prov:              provider.Provider,
	messages:          []provider.Message,
	tools_enabled:     bool,
	reasoning_effort:  string,
	turn_base:         int,
}

session_apply_pending_commit :: proc(s: ^Session) {
	sync.mutex_lock(&s.commit_mu)
	defer sync.mutex_unlock(&s.commit_mu)
	base := s.turn_base
	if base < 0 {
		base = 0
	}
	if base > len(s.messages) {
		base = len(s.messages)
	}
	for len(s.messages) > base {
		last := s.messages[len(s.messages) - 1]
		provider.destroy_message(last)
		pop(&s.messages)
	}
	for m in s.pending_commit {
		append(&s.messages, m)
	}
	clear(&s.pending_commit)
	s.skip_assistant_push = true
	session_maybe_persist(s)
	cap_messages(s)
}

session_queue_commit :: proc(s: ^Session, turn_base: int, msgs: []provider.Message) {
	sync.mutex_lock(&s.commit_mu)
	for m in s.pending_commit {
		provider.destroy_message(m)
	}
	clear(&s.pending_commit)
	s.turn_base = turn_base
	for m in msgs {
		if m.role == .System {
			continue
		}
		cloned := provider.clone_message(m)
		append(&s.pending_commit, cloned)
	}
	sync.mutex_unlock(&s.commit_mu)
	session_enqueue(s, Event{kind = .Turn_Commit})
}

session_request_cancel :: proc(s: ^Session) {
	sync.mutex_lock(&s.control_mu)
	s.cancel_requested = true
	s.pause_requested = false
	sync.mutex_unlock(&s.control_mu)
	http.cancel_request()
	if rt := subagent.runtime(); rt != nil {
		subagent.roster_cancel_children_of(&rt.roster, "main")
	}
	session_set_status(s, "stopping...")
}

session_request_pause :: proc(s: ^Session) {
	sync.mutex_lock(&s.control_mu)
	s.pause_requested = true
	sync.mutex_unlock(&s.control_mu)
	session_set_status(s, "pausing...")
}

session_clear_control :: proc(s: ^Session) {
	sync.mutex_lock(&s.control_mu)
	s.cancel_requested = false
	s.pause_requested = false
	sync.mutex_unlock(&s.control_mu)
	http.cancel_clear()
}

session_stop_check :: proc(user: rawptr) -> agent.Stop_Kind {
	s := cast(^Session)user
	sync.mutex_lock(&s.control_mu)
	defer sync.mutex_unlock(&s.control_mu)
	if s.cancel_requested {
		return .Cancel
	}
	if s.pause_requested {
		return .Pause
	}
	return .None
}

session_resume :: proc(s: ^Session, p: ^provider.Provider, extra := "") {
	if s.busy || p == nil {
		return
	}
	msg := "Continue from where you left off. Use the prior tool results and transcript as context. Do not restart the whole task."
	if len(extra) > 0 {
		msg = fmt.tprintf("%s\n\nAdditional instructions: %s", msg, extra)
	}
	session_push_user(s, msg)
	session_start_chat(s, p)
}

session_start_chat :: proc(s: ^Session, p: ^provider.Provider) {
	if s.busy || p == nil || p.chat == nil {
		return
	}
	session_clear_control(s)

	session_remember_model(s, p.id, p.default_model)

	sys_count := 0
	if len(s.system_prompt) > 0 {
		sys_count = 1
	}
	group_ctx := ""
	if len(s.group) > 0 && group_context_from_env() {
		group_ctx = store.group_context_text(s.group, s.name)
		if len(group_ctx) == 0 {
			delete(group_ctx)
			group_ctx = ""
		} else {
			sys_count += 1
		}
	}
	// Flatten removed: keep native tool_calls and tool role for cache + resume.
	flat := make([dynamic]provider.Message, 0, len(s.messages) + sys_count)
	if len(s.system_prompt) > 0 {
		append(&flat, provider.Message{role = .System, content = strings.clone(s.system_prompt), cacheable = true})
	}
	if len(group_ctx) > 0 {
		append(&flat, provider.Message{role = .System, content = group_ctx})
	}
	for m in s.messages {
		cloned := provider.clone_message(m)
		append(&flat, cloned)
	}
	// Progressive skills: inject matched bodies into the volatile tail (not system prefix).
	last_user := ""
	for i := len(s.messages) - 1; i >= 0; i -= 1 {
		if s.messages[i].role == .User {
			last_user = s.messages[i].content
			break
		}
	}
	if len(last_user) > 0 {
		notes := agent.auto_activate_skill_notes(last_user)
		for note in notes {
			append(&flat, provider.Message{role = .User, content = note})
		}
		delete(notes)
	}
	// Clear-then-compact ladder before the model call.
	session_prepare_context(&flat, p)
	msgs := make([]provider.Message, len(flat))
	copy(msgs, flat[:])
	delete(flat)

	args := new(Job_Args)
	args.session = s
	args.prov = p^
	args.prov.base_url = strings.clone(p.base_url)
	args.prov.api_key = strings.clone(p.api_key)
	args.prov.default_model = strings.clone(p.default_model)
	args.messages = msgs
	args.tools_enabled = s.tools_enabled
	args.reasoning_effort = strings.clone(s.reasoning_effort)
	args.turn_base = len(s.messages)

	status := "waiting for model"
	if s.tools_enabled {
		status = "waiting (agent)"
	}
	session_enqueue(s, Event{kind = .Job_Started, text = strings.clone(status)})
	thread.run_with_data(args, chat_job)
}

@(private)
agent_event_cb :: proc(ev: agent.Event, user: rawptr) {
	s := cast(^Session)user
	switch ev.kind {
	case .Delta:
		session_enqueue(s, Event{kind = .Assistant_Delta, text = strings.clone(ev.text)})
	case .Reasoning_Delta:
		session_enqueue(s, Event{kind = .Reasoning_Delta, text = strings.clone(ev.text)})
	case .Tool_Start:
		line := tools.tool_activity_line(ev.name, ev.text)
		session_enqueue(s, Event{kind = .Tool_Call, text = line, name = strings.clone(ev.name)})
	case .Tool_Done:
		done := fmt.aprintf("%s done", ev.name)
		session_enqueue(s, Event{kind = .Status, text = done, name = strings.clone(ev.name)})
	case .Tool_Message:
		session_enqueue(s, Event{kind = .Tool_Result, text = strings.clone(ev.text), name = strings.clone(ev.name)})
	case .Assistant_Message:
		session_enqueue(s, Event{kind = .Assistant_Turn, text = strings.clone(ev.text)})
	case .Step, .Status:
		session_enqueue(s, Event{kind = .Status, text = strings.clone(ev.text)})
	}
}

@(private)
chat_job :: proc(data: rawptr) {
	args := cast(^Job_Args)data
	defer {
		provider.destroy_messages(args.messages)
		delete(args.messages)
		provider.provider_destroy(&args.prov)
		delete(args.reasoning_effort)
		free(args)
	}

	cfg := agent.default_config()
	cfg.enable_tools = args.tools_enabled
	cfg.reasoning_effort = args.reasoning_effort
	cfg.mode = args.session.agent_mode
	cfg.plan_verify = args.session.plan_verify
	cfg.verify_fail_count = args.session.verify_fail_count
	if args.session.tools_registry != nil {
		cfg.tools_registry = args.session.tools_registry
	}
	cfg.on_event = agent_event_cb
	cfg.user = args.session
	cfg.stop_check = session_stop_check

	args.session.last_input_chars = messages_content_chars(args.messages)

	req := agent.Run_Request{
		prov = &args.prov,
		messages = args.messages,
		tools_enabled = args.tools_enabled,
	}
	result := agent.run_turn(req, cfg)
	args.session.verify_fail_count = result.verify_fail_count
	if result.stopped == "done" &&
		result.verify_fail_count == 0 &&
		args.session.agent_mode == .Edit &&
		agent.turn_had_writes(result.messages[:]) {
		vcmd, voff := agent.resolve_verify_command(args.session.plan_verify)
		if !voff && len(vcmd) > 0 {
			session_add_verify_obligation(args.session, vcmd)
			delete(vcmd)
		}
	}

	if !result.ok {
		msg := result.err
		if len(msg) == 0 {
			msg = "request failed"
		}
		session_enqueue(args.session, Event{kind = .Error, text = strings.clone(msg)})
		delete(result.err)
		if len(result.messages) > 0 {
			provider.destroy_messages(result.messages[:])
			delete(result.messages)
		}
		delete(result.content)
		delete(result.stopped)
		return
	}

	session_enqueue(args.session, Event{
		kind = .Usage,
		prompt_tokens = result.usage.prompt_tokens,
		completion_tokens = result.usage.completion_tokens,
		total_tokens = result.usage.total_tokens,
		reasoning_tokens = result.usage.reasoning_tokens,
		cost_usd = result.usage.cost_usd,
		cost_known = result.usage.cost_known,
		input_chars = args.session.last_input_chars,
		stopped = strings.clone(result.stopped),
	})

	delete(args.session.last_stopped)
	args.session.last_stopped = strings.clone(result.stopped)

	content := result.content
	reasoning := ""
	if len(content) == 0 {
		for i := len(result.messages) - 1; i >= 0; i -= 1 {
			if result.messages[i].role == .Assistant {
				content = result.messages[i].content
				reasoning = result.messages[i].reasoning
				break
			}
		}
	} else {
		for i := len(result.messages) - 1; i >= 0; i -= 1 {
			if result.messages[i].role == .Assistant {
				reasoning = result.messages[i].reasoning
				break
			}
		}
	}
	out := strings.clone(content)
	reason_out := strings.clone(reasoning)
	note := ""
	switch result.stopped {
	case "max_steps":
		note = " (hit step limit)"
	case "paused":
		note = " (paused - /continue to resume)"
	case "cancelled":
		note = " (stopped)"
	case "loop":
		note = " (anti-loop)"
	}

	if args.session.agent_mode == .Plan &&
		(result.stopped == "done" || result.stopped == "max_steps") &&
		len(strings.trim_space(out)) > 0 {
		plan_out := agent.plan_out_from_env(context.temp_allocator)
		out_path := agent.out_path_from_env(context.temp_allocator)
		ws := ""
		if st := sandbox.state(); st != nil {
			ws = st.workspace
		}
		contract := agent.validate_plan_contract(out)
		session_load_plan_contract(args.session, out)
		if !contract.valid {
			session_enqueue(args.session, Event{
				kind = .Status,
				text = strings.clone(fmt.tprintf("plan incomplete: %s", contract.err)),
			})
			agent.done_contract_destroy(&contract)
		} else {
			agent.done_contract_destroy(&contract)
			saved, perr := agent.save_plan_artifact(out, plan_out, out_path, ws)
			if len(perr) > 0 {
				session_enqueue(args.session, Event{kind = .Status, text = strings.clone(fmt.tprintf("plan save failed: %s", perr))})
				delete(perr)
			} else if len(saved) > 0 {
				delete(args.session.last_plan_path)
				args.session.last_plan_path = strings.clone(saved)
				delete(args.session.plan_body)
				args.session.plan_body = strings.clone(strings.trim_space(out))
				session_enqueue(args.session, Event{kind = .Status, text = strings.clone(fmt.tprintf("plan saved %s", saved))})
				delete(saved)
			}
		}
	}

	do_review := agent.review_enabled_from_env() &&
		(result.stopped == "done" || result.stopped == "max_steps" || result.stopped == "verify_failed") &&
		args.tools_enabled &&
		len(out) > 0 &&
		args.session.agent_mode == .Edit
	if do_review {
		session_enqueue(args.session, Event{kind = .Status, text = strings.clone("reviewing...")})
		diff := agent.collect_turn_diff(result.messages[:])
		review_text, review_err := agent.run_review(&args.prov, diff)
		delete(diff)
		if len(review_err) > 0 {
			delete(review_err)
		} else if len(review_text) > 0 {
			blocks, _ := agent.parse_block_findings(review_text)
			combined := strings.concatenate({out, "\n\nreview:\n", review_text})
			delete(out)
			delete(review_text)
			out = combined
			if blocks > 0 && result.stopped == "done" {
				session_enqueue(args.session, Event{
					kind = .Status,
					text = strings.clone(fmt.tprintf("review: %d blocking finding(s)", blocks)),
				})
			}
		}
		if agent.rubric_enabled_from_env() {
			diff2 := agent.collect_turn_diff(result.messages[:])
			rubric_text, rerr := agent.run_rubric(&args.prov, diff2)
			delete(diff2)
			delete(rerr)
			if len(rubric_text) > 0 {
				combined := strings.concatenate({out, "\n\nrubric:\n", rubric_text})
				delete(out)
				delete(rubric_text)
				out = combined
			}
		}
	}

	delete(result.err)
	prefix_n := len(args.messages)
	if len(result.messages) > prefix_n {
		session_queue_commit(args.session, args.turn_base, result.messages[prefix_n:])
	}
	delete(result.stopped)
	if len(result.messages) > 0 {
		provider.destroy_messages(result.messages[:])
		delete(result.messages)
	} else {
		delete(result.content)
	}
	if len(note) > 0 {
		combined := strings.concatenate({out, note})
		delete(out)
		out = combined
	}
	session_enqueue(args.session, Event{kind = .Assistant_Done, text = out, reasoning = reason_out})
}
