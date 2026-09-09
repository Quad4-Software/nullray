// SPDX-License-Identifier: 0BSD

package session

import "core:fmt"
import "core:strings"
import "nullray:agent"
import "nullray:provider"
import "nullray:sandbox"
import "nullray:subagent"
import "nullray:tools"

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
session_prepare_cb :: proc(
	msgs: ^[dynamic]provider.Message,
	p: ^provider.Provider,
	user: rawptr,
) -> agent.Prepare_Stats {
	stats := session_prepare_context(msgs, p)
	s := cast(^Session)user
	if s != nil && session_writeback_prepare(s, msgs[:], stats) {
		stats.writeback = true
	}
	return stats
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
	cfg.prepare_context = session_prepare_cb
	agent.hunt_log_sampling(cfg.hunt)

	args.session.last_input_chars = messages_content_chars(args.messages)

	req := agent.Run_Request{
		prov = &args.prov,
		messages = args.messages,
		tools_enabled = args.tools_enabled,
	}
	result := agent.run_turn(req, cfg)
	args.session.verify_fail_count = result.verify_fail_count
	result.harness.clear_events += args.prep_stats.cleared
	if args.prep_stats.compacted {
		result.harness.compact_events += 1
	}
	if args.prep_stats.writeback {
		result.harness.writeback_events += 1
	}
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
		harness_calls = result.harness.call_count,
		harness_peak_chars = result.harness.peak_prompt_chars,
		harness_stubbed = result.harness.stubbed_bytes,
		harness_artifacts = result.harness.artifacts_stored,
		harness_clear = result.harness.clear_events,
		harness_compact = result.harness.compact_events,
		harness_midturn = result.harness.midturn_prepare_events,
		harness_writeback = result.harness.writeback_events,
		harness_tools_json = result.harness.tools_json_chars,
	})

	// Child turns write usage files but do not emit session events. Roll pending
	// locate/task tokens into subagent_total_tokens before the parent turn ends.
	if rt := subagent.runtime(); rt != nil {
		if kids := subagent.runtime_take_child_tokens(rt); kids > 0 {
			session_enqueue(args.session, Event{
				kind = .Usage,
				agent_id = strings.clone("subagents"),
				total_tokens = kids,
			})
		}
	}

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
