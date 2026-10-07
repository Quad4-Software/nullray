// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Agent turn loop body: chat steps, tools, verify, and LID prepare.
*/

package agent

import "core:fmt"
import "core:strings"
import "nullray:constants"
import "nullray:experience"
import "nullray:hooks"
import "nullray:provider"
import "nullray:tools"

run_turn_inner :: proc(req: Run_Request, cfg: Config, allocator := context.allocator) -> Run_Result {
	if req.prov == nil || req.prov.chat == nil {
		return Run_Result{ok = false, err = strings.clone("no provider", allocator)}
	}
	start_hook := hooks.run(.SessionStart, allocator = allocator)
	if start_hook.blocked {
		return Run_Result{ok = false, err = start_hook.message}
	}
	hooks.result_destroy(&start_hook, allocator)
	defer {
		end_hook := hooks.run(.SessionEnd, allocator = context.temp_allocator)
		hooks.result_destroy(&end_hook, context.temp_allocator)
		stop_hook := hooks.run(.Stop, allocator = context.temp_allocator)
		hooks.result_destroy(&stop_hook, context.temp_allocator)
	}

	msgs := clone_messages(req.messages, allocator)
	todo_turn := turn_todo_begin(cfg, &msgs, allocator)
	defer turn_todo_end(todo_turn)
	tools_on := req.tools_enabled && cfg.enable_tools
	tools_json := ""
	mode_s := mode_string(cfg.mode)
	reg := cfg.tools_registry
	if reg == nil {
		reg = tools.registry()
	}
	harness: Harness_Metrics
	model := req.model
	if len(model) == 0 {
		model = req.prov.default_model
	}
	if tools_on {
		tools_json = tools.openai_tools_json(reg, mode_s, prompt_tier_for_model(req.prov.id, model), allocator, cfg.tool_allow, req.prov.id)
		harness.tools_json_chars = len(tools_json)
	}
	defer if len(tools_json) > 0 {
		delete(tools_json)
	}

	max_steps := 1
	if tools_on {
		max_steps = cfg.max_steps
		if max_steps <= 0 {
			max_steps = constants.MAX_AGENT_STEPS
		}
	}
	shim_model, shim_on := toolshim_model(model)
	shim_attempts := 0
	last_content := ""
	usage_sum: provider.Usage
	cost_all_known := true
	saw_cost := false
	loop_det := loop_detector_init(allocator)
	defer loop_detector_destroy(&loop_det)
	embed_ctx := Loop_Embed_Ctx{prov = req.prov, model = provider.resolve_embed_model(req.prov)}
	if sem := loop_sem_mode_from_env(req.prov.embed != nil); sem != .Off {
		embed_proc: Loop_Embed_Proc
		if sem == .Embed {
			embed_proc = loop_embed_bridge
		}
		loop_detector_set_semantic(&loop_det, sem, embed_proc, &embed_ctx)
	}
	esc := escalate_state_init(allocator)
	defer escalate_state_destroy(&esc)
	loop_tier := Loop_Tier.None
	step_sig := u64(0)
	malformed_left := tool_retry_budget()
	prev_asst := ""
	asst_streak := 0
	verify_fails := cfg.verify_fail_count
	verify_test_nudged := false
	had_writes := false
	had_tools := false
	finalize_nudged := false
	verify_ran := false

	cfg_local := cfg
	spec_pool: tools.Speculate_Pool
	spec_live := false
	if cfg.speculate && tools_on {
		tools.speculate_pool_init(&spec_pool, reg, mode_s, cfg.speculate_parallel, allocator, cfg.tool_allow)
		cfg_local.speculate_pool = &spec_pool
		spec_live = true
	}
	defer if spec_live {
		tools.speculate_pool_destroy(&spec_pool)
	}

	for step in 0 ..< max_steps {
		loop_tier = .None
		switch check_stop(cfg_local) {
		case .Cancel:
			tools.speculate_discard_all(cfg_local.speculate_pool)
			emit(cfg_local, .Status, "cancelled")
			harness_log_metrics(harness)
			return finish_run(Run_Result{ok = true, messages = msgs, content = last_content, stopped = owned_stop("cancelled", allocator), usage = usage_sum, harness = harness}, &esc, allocator)
		case .Pause:
			tools.speculate_stop_admit(cfg_local.speculate_pool)
			emit(cfg_local, .Status, "paused")
			harness_log_metrics(harness)
			return finish_run(Run_Result{ok = true, messages = msgs, content = last_content, stopped = owned_stop("paused", allocator), usage = usage_sum, harness = harness}, &esc, allocator)
		case .None:
		}

		if tools_on {
			emit(cfg_local, .Step, fmt.tprintf("step %d/%d", step + 1, max_steps))
		}
		prompt_chars := messages_content_chars(msgs[:])
		harness_record_call(&harness, prompt_chars)
		step_tools := tools_json
		if finalize_nudged {
			step_tools = ""
		}
		res := escalate_chat_step(req.prov, msgs[:], model, step_tools, cfg_local, &esc, &harness, allocator)
		if !res.ok {
			provider.destroy_messages(msgs[:])
			delete(msgs)
			harness_log_metrics(harness)
			return finish_run(Run_Result{ok = false, err = res.err, usage = usage_sum, harness = harness}, &esc, allocator)
		}
		usage_sum.prompt_tokens += res.usage.prompt_tokens
		usage_sum.completion_tokens += res.usage.completion_tokens
		usage_sum.total_tokens += res.usage.total_tokens
		usage_sum.reasoning_tokens += res.usage.reasoning_tokens
		step_tokens := res.usage.prompt_tokens + res.usage.completion_tokens + res.usage.total_tokens
		if res.usage.cost_known {
			usage_sum.cost_usd += res.usage.cost_usd
			saw_cost = true
		} else if step_tokens > 0 {
			cost_all_known = false
		}
		usage_sum.cost_known = saw_cost && cost_all_known
		if usage_sum.total_tokens == 0 {
			usage_sum.total_tokens = usage_sum.prompt_tokens + usage_sum.completion_tokens
		}

		calls := res.tool_calls
		text_calls := false
		if tools_on && len(calls) == 0 {
			calls = parse_tool_calls_text(res.content, allocator)
			text_calls = true
			// Toolshim: text still looks like an attempted tool call but
			// salvage found nothing. One side chat converts it.
			if len(calls) == 0 && !finalize_nudged && shim_on &&
			   shim_attempts < TOOLSHIM_MAX_PER_TURN &&
			   shim_text_looks_toolish(res.content, reg) {
				shim_attempts += 1
				shim_calls, shim_ok := turn_toolshim_attempt(
					req.prov, shim_model, res.content, reg, mode_s,
					cfg_local.tool_allow, shim_attempts, &usage_sum, &saw_cost,
					&cost_all_known, allocator,
				)
				if shim_ok {
					calls = shim_calls
					emit(cfg, .Status, "toolshim: converted text to tool call")
				} else {
					emit(cfg, .Status, "toolshim: conversion failed")
				}
			}
		}

		if len(calls) == 0 && len(res.content) > 0 {
			if res.content == prev_asst {
				asst_streak += 1
			} else {
				asst_streak = 1
				prev_asst = res.content
			}
		if asst_streak >= constants.MAX_IDENTICAL_ASSISTANT_LOOPS {
				turn_discard_chat_extras(&res, calls, text_calls)
				emit(cfg, .Status, "anti-loop: repeated reply")
				append(&msgs, provider.Message{role = .Assistant, content = res.content, reasoning = res.reasoning})
				harness_log_metrics(harness)
				return finish_run(Run_Result{ok = true, messages = msgs, content = res.content, stopped = owned_stop("loop", allocator), usage = usage_sum, harness = harness}, &esc, allocator)
			}
		}

		if len(calls) > 0 {
			step_sig = loop_sig_of_calls(calls)
			stop, tier, stall, loop_res := turn_loop_gate(
				&msgs, &loop_det, calls, step_sig,
				&res, text_calls, cfg, usage_sum, harness, allocator,
			)
			if stop {
				harness_log_metrics(harness)
				return finish_run(loop_res, &esc, allocator)
			}
			loop_tier = tier
			if stall {
				escalate_should(&esc, true, step_sig)
			}
		}

		asst := provider.Message{
			role = .Assistant,
			content = res.content,
			reasoning = res.reasoning,
		}
		if len(calls) > 0 {
			asst.tool_calls = make([]provider.Tool_Call, len(calls), allocator)
			for c, i in calls {
				asst.tool_calls[i] = provider.clone_tool_call(c, allocator)
			}
		}
		append(&msgs, asst)
		last_content = res.content
		if len(res.reasoning) > 0 && !cfg.stream {
			emit(cfg, .Reasoning_Delta, res.reasoning)
		}
		if len(calls) > 0 {
			emit(cfg, .Assistant_Message, res.content)
		}

		if !tools_on || len(calls) == 0 {
			turn_discard_chat_extras(&res, calls, text_calls)

			if turn_needs_finalize(last_content, had_tools, finalize_nudged) {
				finalize_nudged = true
				turn_append_finalize_nudge(&msgs, allocator)
				emit(cfg, .Status, "harness: finalize after tools")
				continue
			}

			v_out, v_res := turn_verify_on_assistant_done(
				&msgs,
				cfg,
				reg,
				tools_on,
				had_writes,
				usage_sum,
				&verify_fails,
				&verify_test_nudged,
				harness,
				allocator,
			)
			switch v_out {
			case .Continue:
				verify_ran = true
				continue
			case .Failed_Stop:
				v_res.verify_ran = true
				return finish_run(v_res, &esc, allocator)
			case .Ok:
				verify_ran = true
			case .Skipped:
			}

			harness_log_metrics(harness)
			return finish_run(Run_Result{
				ok = true,
				messages = msgs,
				content = last_content,
				stopped = owned_stop("done", allocator),
				usage = usage_sum,
				verify_fail_count = verify_fails,
				verify_ran = verify_ran,
				harness = harness,
			}, &esc, allocator)
		}

		elevate_stop, step_writes, step_rh, malformed, mal_kind, step_snip := turn_exec_tool_calls(
			&msgs,
			cfg_local,
			reg,
			mode_s,
			calls,
			loop_tier,
			loop_call_names(calls),
			&malformed_left,
			&harness,
			allocator,
		)
		loop_detector_observe(&loop_det, step_sig, step_rh, step_snip, calls)
		delete(step_snip)
		tools.checkpoint_commit_step(step + 1)
		if malformed {
			turn_restart_malformed(&msgs, mal_kind, malformed_kind_name(mal_kind), malformed_left > 0, allocator)
			emit(cfg, .Status, "harness: dropped malformed tool call")
			turn_discard_chat_extras(&res, calls, text_calls)
			continue
		}
		if step_writes {
			had_writes = true
		}
		had_tools = true

		turn_discard_chat_extras(&res, calls, text_calls)

		if elevate_stop {
			msg := strings.clone(
				"Stopped: elevation auth failed, was cancelled, or is locked. Tell the human; do not retry with passwords.",
				allocator,
			)
			emit(cfg, .Status, "elevate: non-retryable")
			append(&msgs, provider.Message{role = .Assistant, content = msg})
			harness_log_metrics(harness)
			return finish_run(Run_Result{
				ok = true,
				messages = msgs,
				content = msg,
				stopped = owned_stop("elevate", allocator),
				usage = usage_sum,
				harness = harness,
			}, &esc, allocator)
		}

		turn_mid_prepare(&msgs, cfg, req.prov, had_writes, &harness)
		turn_inject_steer(&msgs, cfg_local, allocator)

		if check_stop(cfg) == .Cancel {
			harness_log_metrics(harness)
			return finish_run(Run_Result{ok = true, messages = msgs, content = last_content, stopped = owned_stop("cancelled", allocator), usage = usage_sum, harness = harness}, &esc, allocator)
		}
		if check_stop(cfg) == .Pause {
			emit(cfg, .Status, "paused")
			harness_log_metrics(harness)
			return finish_run(Run_Result{ok = true, messages = msgs, content = last_content, stopped = owned_stop("paused", allocator), usage = usage_sum, harness = harness}, &esc, allocator)
		}
	}

	if turn_needs_finalize(last_content, had_tools, finalize_nudged) {
		if turn_finalize_after_max_steps(
			&msgs,
			req,
			model,
			cfg_local,
			&harness,
			&usage_sum,
			&saw_cost,
			&cost_all_known,
			&last_content,
			allocator,
		) {
			harness_log_metrics(harness)
			return finish_run(Run_Result{
				ok = true,
				messages = msgs,
				content = last_content,
				stopped = owned_stop("done", allocator),
				usage = usage_sum,
				verify_fail_count = verify_fails,
				verify_ran = verify_ran,
				harness = harness,
			}, &esc, allocator)
		}
	}

	if did, v_res := turn_verify_on_step_budget(
		&msgs,
		cfg,
		reg,
		tools_on,
		had_writes,
		last_content,
		usage_sum,
		&verify_fails,
		harness,
		allocator,
	); did {
		v_res.verify_ran = true
		return finish_run(v_res, &esc, allocator)
	}

	harness_log_metrics(harness)
	return finish_run(Run_Result{
		ok = true,
		messages = msgs,
		content = last_content,
		err = strings.clone("max agent steps reached", allocator),
		stopped = owned_stop("max_steps", allocator),
		usage = usage_sum,
		verify_fail_count = verify_fails,
		verify_ran = verify_ran,
		harness = harness,
	}, &esc, allocator)
}

/*
Turn-end seam: distill each completed session turn into the experience
index. session_id is only set for real session workers (TUI, print, ACP),
so scripted run_turn tests never touch the store.
*/
run_turn :: proc(req: Run_Request, cfg: Config, allocator := context.allocator) -> Run_Result {
	res := run_turn_inner(req, cfg, allocator)
	if len(cfg.session_id) > 0 {
		experience.exp_record_turn(
			req.messages, res.messages[:],
			res.ok, res.stopped, res.err, res.content, res.escalations,
		)
	}
	return res
}
