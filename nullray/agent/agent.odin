// SPDX-License-Identifier: 0BSD
/*
Agent turn loop: config, stop checks, anti-loop, tool execution.
*/

package agent

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "nullray:constants"
import "nullray:elevate"
import "nullray:provider"
import "nullray:sandbox"
import "nullray:tools"

Stop_Kind :: enum {
	None,
	Cancel,
	Pause,
}

Stop_Check :: #type proc(user: rawptr) -> Stop_Kind

Config :: struct {
	max_steps:         int,
	enable_tools:      bool,
	stream:            bool,
	reasoning_effort:  string,
	max_tokens:        int,
	mode:              Agent_Mode,
	tools_registry:    ^tools.Registry,
	on_event:          Event_Proc,
	user:              rawptr,
	stop_check:        Stop_Check,
	plan_verify:       string,
	verify_fail_count: int,
}

Event_Kind :: enum {
	Status,
	Tool_Start,
	Tool_Done,
	Step,
	Delta,
	Reasoning_Delta,
	Assistant_Message,
	Tool_Message,
}

Event :: struct {
	kind: Event_Kind,
	text: string,
	name: string,
}

Event_Proc :: #type proc(ev: Event, user: rawptr)

default_config :: proc() -> Config {
	steps := constants.MAX_AGENT_STEPS
	if auto_from_env() {
		steps = 40
	}
	if v, ok := os.lookup_env(constants.ENV_AGENT_STEPS, context.temp_allocator); ok {
		n, n_ok := strconv.parse_int(v)
		if n_ok && n > 0 {
			steps = n
		}
	}
	stream := true
	if v, ok := os.lookup_env(constants.ENV_STREAM, context.temp_allocator); ok {
		if v == "0" || v == "false" || v == "off" {
			stream = false
		}
	}
	effort := constants.DEFAULT_REASONING
	if v, ok := os.lookup_env(constants.ENV_REASONING, context.temp_allocator); ok && len(v) > 0 {
		effort = strings.to_lower(v, context.temp_allocator)
	}
	max_tokens := constants.DEFAULT_MAX_TOKENS
	if v, ok := os.lookup_env(constants.ENV_MAX_TOKENS, context.temp_allocator); ok {
		n, n_ok := strconv.parse_int(v)
		if n_ok && n > 0 {
			max_tokens = n
		}
	}
	return Config{
		max_steps = steps,
		enable_tools = true,
		stream = stream,
		reasoning_effort = effort,
		max_tokens = max_tokens,
		mode = mode_from_env(),
		tools_registry = tools.registry(),
	}
}

Run_Request :: struct {
	prov:          ^provider.Provider,
	messages:      []provider.Message,
	tools_enabled: bool,
	model:         string,
}

Run_Result :: struct {
	ok:                bool,
	messages:          [dynamic]provider.Message,
	content:           string,
	err:               string,
	stopped:           string,
	usage:             provider.Usage,
	verify_fail_count: int,
}

emit :: proc(cfg: Config, kind: Event_Kind, text: string, name := "") {
	if cfg.on_event != nil {
		cfg.on_event(Event{kind = kind, text = text, name = name}, cfg.user)
	}
}

check_stop :: proc(cfg: Config) -> Stop_Kind {
	if cfg.stop_check == nil {
		return .None
	}
	return cfg.stop_check(cfg.user)
}

tool_fingerprint :: proc(calls: []provider.Tool_Call, allocator := context.temp_allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	for c in calls {
		strings.write_string(&b, c.name)
		strings.write_byte(&b, '|')
		strings.write_string(&b, c.arguments)
		strings.write_byte(&b, ';')
	}
	return strings.to_string(b)
}

result_prefix_had_writes :: proc(messages: []provider.Message) -> bool {
	return turn_had_writes(messages)
}

owned_stop :: proc(kind: string, allocator := context.allocator) -> string {
	return strings.clone(kind, allocator)
}

clear_msgs_tool_results :: proc(msgs: ^[dynamic]provider.Message, keep: int) -> int {
	if msgs == nil || keep < 0 {
		return 0
	}
	tool_idxs := make([dynamic]int, context.temp_allocator)
	for m, i in msgs {
		if m.role == .Tool {
			append(&tool_idxs, i)
		}
	}
	if len(tool_idxs) <= keep {
		return 0
	}
	cleared := 0
	cutoff := len(tool_idxs) - keep
	for ti in 0 ..< cutoff {
		i := tool_idxs[ti]
		m := msgs[i]
		if strings.has_prefix(m.content, constants.TOOL_CLEAR_STUB_PREFIX) {
			continue
		}
		name := m.name
		if len(name) == 0 {
			name = "tool"
		}
		stub := fmt.aprintf("%s %s %d bytes; re-call if needed]", constants.TOOL_CLEAR_STUB_PREFIX, name, len(m.content), allocator = msgs.allocator)
		delete(m.content)
		msgs[i].content = stub
		cleared += 1
	}
	return cleared
}

run_turn :: proc(req: Run_Request, cfg: Config, allocator := context.allocator) -> Run_Result {
	if req.prov == nil || req.prov.chat == nil {
		return Run_Result{ok = false, err = strings.clone("no provider", allocator)}
	}

	msgs := clone_messages(req.messages, allocator)
	tools_on := req.tools_enabled && cfg.enable_tools
	tools_json := ""
	mode_s := mode_string(cfg.mode)
	reg := cfg.tools_registry
	if reg == nil {
		reg = tools.registry()
	}
	if tools_on {
		// Own across every chat step. Stream callbacks must not free this.
		tools_json = tools.openai_tools_json(reg, mode_s, allocator)
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
	prev_tool_fp := ""
	tool_fp_streak := 0
	prev_asst := ""
	asst_streak := 0
	verify_fails := cfg.verify_fail_count

	for step in 0 ..< max_steps {
		switch check_stop(cfg) {
		case .Cancel:
			emit(cfg, .Status, "cancelled")
			return Run_Result{ok = true, messages = msgs, content = last_content, stopped = owned_stop("cancelled", allocator), usage = usage_sum}
		case .Pause:
			emit(cfg, .Status, "paused")
			return Run_Result{ok = true, messages = msgs, content = last_content, stopped = owned_stop("paused", allocator), usage = usage_sum}
		case .None:
		}

		if tools_on {
			emit(cfg, .Step, fmt.tprintf("step %d/%d", step + 1, max_steps))
		}
		res := single_chat(req.prov, msgs[:], model, tools_json, cfg, allocator)
		if !res.ok {
			provider.destroy_messages(msgs[:])
			delete(msgs)
			return Run_Result{ok = false, err = res.err, usage = usage_sum}
		}
		usage_sum.prompt_tokens += res.usage.prompt_tokens
		usage_sum.completion_tokens += res.usage.completion_tokens
		usage_sum.total_tokens += res.usage.total_tokens
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
				return Run_Result{ok = true, messages = msgs, content = res.content, stopped = owned_stop("loop", allocator), usage = usage_sum}
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
				delete(res.model)
				delete(res.err)
				delete(res.finish_reason)
				if text_calls {
					provider.destroy_tool_calls(calls)
				} else {
					provider.destroy_tool_calls(res.tool_calls)
				}
				msg := strings.clone(
					"Stopped: repeated the same tool calls. Adjust the approach or /continue with new instructions.",
					allocator,
				)
				emit(cfg, .Status, "anti-loop: repeated tools")
				append(&msgs, provider.Message{role = .Assistant, content = msg})
				return Run_Result{ok = true, messages = msgs, content = msg, stopped = owned_stop("loop", allocator), usage = usage_sum}
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

			// Verify stop gate when the model claims done after writes (opt-in).
			if tools_on &&
				cfg.mode == .Edit &&
				(result_prefix_had_writes(msgs[:]) || turn_had_writes(msgs[:])) {
				vcmd, voff := resolve_verify_command(cfg.plan_verify, context.temp_allocator)
				if !voff && len(vcmd) > 0 {
					vargs := fmt.aprintf(`{{"command":%q}}`, vcmd, allocator = context.temp_allocator)
					emit(cfg, .Status, fmt.tprintf("verify: %s", vcmd))
					emit(cfg, .Tool_Start, vargs, "verify")
					vok, vout := run_verify_command(vcmd, reg, allocator)
					emit(cfg, .Tool_Done, vout, "verify")
					if !vok {
						verify_fails += 1
						max_fails := verify_max_fails_from_env()
						if verify_fails >= max_fails {
							fail_msg := format_verify_nudge(vcmd, verify_fails, max_fails, vout, true, allocator)
							delete(vout)
							emit(cfg, .Status, "verify failed (breaker)")
							append(&msgs, provider.Message{role = .User, content = fail_msg})
							return Run_Result{
								ok = true,
								messages = msgs,
								content = fail_msg,
								stopped = owned_stop("verify_failed", allocator),
								usage = usage_sum,
								verify_fail_count = verify_fails,
							}
						}
						nudge := format_verify_nudge(vcmd, verify_fails, max_fails, vout, false, allocator)
						delete(vout)
						emit(cfg, .Status, fmt.tprintf("verify failed (%d/%d)", verify_fails, max_fails))
						append(&msgs, provider.Message{role = .User, content = nudge})
						continue
					}
					delete(vout)
					emit(cfg, .Status, "verify ok")
					verify_fails = 0
				}
			}

			return Run_Result{
				ok = true,
				messages = msgs,
				content = last_content,
				stopped = owned_stop("done", allocator),
				usage = usage_sum,
				verify_fail_count = verify_fails,
			}
		}

		elevate_stop := false
		for c in calls {
			if check_stop(cfg) == .Cancel {
				break
			}
			emit(cfg, .Tool_Start, c.arguments, c.name)
			tool_result, tool_err := tools.run(reg, c.name, c.arguments, mode_s, allocator)
			raw := tool_result
			if len(tool_err) > 0 {
				raw = tool_err
			}
			result_text := sandbox.redact_secrets(raw, allocator)
			delete(tool_result)
			delete(tool_err)
			emit(cfg, .Tool_Done, result_text, c.name)
			emit(cfg, .Tool_Message, result_text, c.name)
			append(&msgs, provider.Message{
				role = .Tool,
				content = result_text,
				tool_call_id = strings.clone(c.id, allocator),
				name = strings.clone(c.name, allocator),
			})
			if elevate.is_nonretryable_elevate_text(result_text) {
				elevate_stop = true
			}
			if c.name == "compact_context" {
				_ = clear_msgs_tool_results(&msgs, 2)
			}
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
			return Run_Result{
				ok = true,
				messages = msgs,
				content = msg,
				stopped = owned_stop("elevate", allocator),
				usage = usage_sum,
			}
		}

		if check_stop(cfg) == .Cancel {
			return Run_Result{ok = true, messages = msgs, content = last_content, stopped = owned_stop("cancelled", allocator), usage = usage_sum}
		}
		if check_stop(cfg) == .Pause {
			emit(cfg, .Status, "paused")
			return Run_Result{ok = true, messages = msgs, content = last_content, stopped = owned_stop("paused", allocator), usage = usage_sum}
		}
	}

	return Run_Result{
		ok = true,
		messages = msgs,
		content = last_content,
		err = strings.clone("max agent steps reached", allocator),
		stopped = owned_stop("max_steps", allocator),
		usage = usage_sum,
		verify_fail_count = verify_fails,
	}
}
