// SPDX-License-Identifier: 0BSD
/*
Agent turn loop body: chat steps, tools, verify, and LID prepare.
*/

package agent

import "core:fmt"
import "core:strings"
import "nullray:constants"
import "nullray:hooks"
import "nullray:provider"
import "nullray:tools"

run_turn :: proc(req: Run_Request, cfg: Config, allocator := context.allocator) -> Run_Result {
	if req.prov == nil || req.prov.chat == nil {
		return Run_Result{ok = false, err = strings.clone("no provider", allocator)}
	}
	start_hook := hooks.run(.SessionStart, allocator = allocator)
	if start_hook.blocked {
		return Run_Result{ok = false, err = start_hook.message}
	}
	delete(start_hook.message)
	defer {
		end_hook := hooks.run(.SessionEnd, allocator = context.temp_allocator)
		delete(end_hook.message)
		stop_hook := hooks.run(.Stop, allocator = context.temp_allocator)
		delete(stop_hook.message)
	}

	msgs := clone_messages(req.messages, allocator)
	tools_on := req.tools_enabled && cfg.enable_tools
	tools_json := ""
	mode_s := mode_string(cfg.mode)
	reg := cfg.tools_registry
	if reg == nil {
		reg = tools.registry()
	}
	harness: Harness_Metrics
	if tools_on {
		// Own across every chat step. Stream callbacks must not free this.
		tools_json = tools.openai_tools_json(reg, mode_s, prompt_lean_enabled(), allocator, cfg.tool_allow)
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
	model := req.model
	if len(model) == 0 {
		model = req.prov.default_model
	}
	last_content := ""
	usage_sum: provider.Usage
	cost_all_known := true
	saw_cost := false
	prev_tool_fp := ""
	tool_fp_streak := 0
	intervened_tool_fp := ""
	loop_intervene := false
	prev_asst := ""
	asst_streak := 0
	verify_fails := cfg.verify_fail_count
	had_writes := false
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
		loop_intervene = false
		switch check_stop(cfg_local) {
		case .Cancel:
			tools.speculate_discard_all(cfg_local.speculate_pool)
			emit(cfg_local, .Status, "cancelled")
			harness_log_metrics(harness)
			return Run_Result{ok = true, messages = msgs, content = last_content, stopped = owned_stop("cancelled", allocator), usage = usage_sum, harness = harness}
		case .Pause:
			tools.speculate_stop_admit(cfg_local.speculate_pool)
			emit(cfg_local, .Status, "paused")
			harness_log_metrics(harness)
			return Run_Result{ok = true, messages = msgs, content = last_content, stopped = owned_stop("paused", allocator), usage = usage_sum, harness = harness}
		case .None:
		}

		if tools_on {
			emit(cfg_local, .Step, fmt.tprintf("step %d/%d", step + 1, max_steps))
		}
		prompt_chars := messages_content_chars(msgs[:])
		harness_record_call(&harness, prompt_chars)
		res := single_chat(req.prov, msgs[:], model, tools_json, cfg_local, &harness, allocator)
		if !res.ok {
			provider.destroy_messages(msgs[:])
			delete(msgs)
			harness_log_metrics(harness)
			return Run_Result{ok = false, err = res.err, usage = usage_sum, harness = harness}
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
		}

		if len(calls) == 0 && len(res.content) > 0 {
			if res.content == prev_asst {
				asst_streak += 1
			} else {
				asst_streak = 1
				prev_asst = res.content
			}
			if asst_streak >= constants.MAX_IDENTICAL_ASSISTANT_LOOPS {
				delete(res.model)
				delete(res.err)
				delete(res.finish_reason)
				if text_calls {
					provider.destroy_tool_calls(calls)
				} else {
					provider.destroy_tool_calls(res.tool_calls)
				}
				emit(cfg, .Status, "anti-loop: repeated reply")
				append(&msgs, provider.Message{role = .Assistant, content = res.content, reasoning = res.reasoning})
				harness_log_metrics(harness)
				return Run_Result{ok = true, messages = msgs, content = res.content, stopped = owned_stop("loop", allocator), usage = usage_sum, harness = harness}
			}
		}

		if len(calls) > 0 {
			fp := tool_fingerprint(calls)
			if fp == prev_tool_fp {
				tool_fp_streak += 1
			} else {
				tool_fp_streak = 1
				prev_tool_fp = strings.clone(fp, context.temp_allocator)
			}
			if tool_fp_streak >= constants.MAX_IDENTICAL_TOOL_LOOPS {
				if len(intervened_tool_fp) > 0 && fp == intervened_tool_fp {
					delete(res.model)
					delete(res.err)
					delete(res.finish_reason)
					if text_calls {
						provider.destroy_tool_calls(calls)
					} else {
						provider.destroy_tool_calls(res.tool_calls)
					}
					msg := strings.clone(
						"Stopped: repeated the same tool calls after a loop warning. Adjust the approach or /continue with new instructions.",
						allocator,
					)
					emit(cfg, .Status, "anti-loop: repeated tools after intervene")
					append(&msgs, provider.Message{role = .Assistant, content = msg})
					harness_log_metrics(harness)
					return Run_Result{ok = true, messages = msgs, content = msg, stopped = owned_stop("loop", allocator), usage = usage_sum, harness = harness}
				}
				intervened_tool_fp = strings.clone(fp, context.temp_allocator)
				tool_fp_streak = 0
				loop_intervene = true
				emit(cfg, .Status, "anti-loop: intervene")
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
			delete(res.model)
			delete(res.err)
			delete(res.finish_reason)
			if text_calls {
				provider.destroy_tool_calls(calls)
			} else {
				provider.destroy_tool_calls(res.tool_calls)
			}

			v_out, v_res := turn_verify_on_assistant_done(
				&msgs,
				cfg,
				reg,
				tools_on,
				had_writes,
				usage_sum,
				&verify_fails,
				harness,
				allocator,
			)
			switch v_out {
			case .Continue:
				verify_ran = true
				continue
			case .Failed_Stop:
				v_res.verify_ran = true
				return v_res
			case .Ok:
				verify_ran = true
			case .Skipped:
			}

			harness_log_metrics(harness)
			return Run_Result{
				ok = true,
				messages = msgs,
				content = last_content,
				stopped = owned_stop("done", allocator),
				usage = usage_sum,
				verify_fail_count = verify_fails,
				verify_ran = verify_ran,
				harness = harness,
			}
		}

		elevate_stop, step_writes := turn_exec_tool_calls(
			&msgs,
			cfg_local,
			reg,
			mode_s,
			calls,
			loop_intervene,
			&harness,
			allocator,
		)
		if step_writes {
			had_writes = true
		}

		delete(res.model)
		delete(res.err)
		delete(res.finish_reason)
		if text_calls {
			provider.destroy_tool_calls(calls)
		} else {
			provider.destroy_tool_calls(res.tool_calls)
		}

		if elevate_stop {
			msg := strings.clone(
				"Stopped: elevation auth failed, was cancelled, or is locked. Tell the human; do not retry with passwords.",
				allocator,
			)
			emit(cfg, .Status, "elevate: non-retryable")
			append(&msgs, provider.Message{role = .Assistant, content = msg})
			harness_log_metrics(harness)
			return Run_Result{
				ok = true,
				messages = msgs,
				content = msg,
				stopped = owned_stop("elevate", allocator),
				usage = usage_sum,
				harness = harness,
			}
		}

		turn_mid_prepare(&msgs, cfg, req.prov, had_writes, &harness)

		if check_stop(cfg) == .Cancel {
			harness_log_metrics(harness)
			return Run_Result{ok = true, messages = msgs, content = last_content, stopped = owned_stop("cancelled", allocator), usage = usage_sum, harness = harness}
		}
		if check_stop(cfg) == .Pause {
			emit(cfg, .Status, "paused")
			harness_log_metrics(harness)
			return Run_Result{ok = true, messages = msgs, content = last_content, stopped = owned_stop("paused", allocator), usage = usage_sum, harness = harness}
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
		return v_res
	}

	harness_log_metrics(harness)
	return Run_Result{
		ok = true,
		messages = msgs,
		content = last_content,
		err = strings.clone("max agent steps reached", allocator),
		stopped = owned_stop("max_steps", allocator),
		usage = usage_sum,
		verify_fail_count = verify_fails,
		verify_ran = verify_ran,
		harness = harness,
	}
}
