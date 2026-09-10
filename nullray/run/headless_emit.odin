// SPDX-License-Identifier: 0BSD
package run

import "core:fmt"
import "core:os"
import "core:strings"
import "nullray:agent"
import "nullray:constants"
import "nullray:provider"
import "nullray:session"

@(private)
print_strict_from_env :: proc() -> bool {
	if v, ok := os.lookup_env(constants.ENV_PRINT_STRICT, context.temp_allocator); ok {
		switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
		case "1", "true", "yes", "on":
			return true
		}
	}
	return false
}

@(private)
print_usage_from_env :: proc() -> bool {
	if v, ok := os.lookup_env(constants.ENV_PRINT_USAGE, context.temp_allocator); ok {
		switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
		case "1", "true", "yes", "on":
			return true
		}
	}
	return false
}

@(private)
print_strict_fail :: proc(s: ^session.Session, res: Result, living: int, tool_only: bool) -> (bool, string) {
	if s.agent_mode == .Plan && !s.plan_contract_ok {
		return true, "print-strict: plan Done Contract incomplete"
	}
	if s.verify_fail_count > 0 || res.stopped == "verify_failed" {
		return true, "print-strict: verify failed"
	}
	if s.agent_mode == .Edit && res.stopped == "done" {
		had_writes := agent.turn_had_writes(s.messages[:])
		if had_writes {
			_, voff := agent.resolve_verify_command(s.plan_verify, context.temp_allocator)
			if !voff && !s.verify_ran {
				return true, "print-strict: verify did not run after writes"
			}
		}
	}
	switch res.stopped {
	case "loop", "timeout":
		return true, fmt.tprintf("print-strict: stopped with %s", res.stopped)
	case "max_steps":
		had_writes := agent.turn_had_writes(s.messages[:])
		had_tools := agent.turn_had_tool_calls(s.messages[:])
		if !had_writes && !had_tools {
			return true, "print-strict: stopped with max_steps"
		}
	}
	if living > 0 {
		return true, fmt.tprintf("print-strict: %d subagent(s) still running", living)
	}
	if tool_only && s.agent_mode == .Edit {
		had_writes := agent.turn_had_writes(s.messages[:])
		if had_writes {
			_, voff := agent.resolve_verify_command(s.plan_verify, context.temp_allocator)
			if !voff {
				return true, "print-strict: tool-only turn with writes and verify enabled"
			}
		} else {
			return true, "print-strict: tool-only turn with no workspace writes"
		}
	}
	return false, ""
}

emit_result :: proc(cfg: Config, res: Result) {
	format := strings.to_lower(strings.trim_space(cfg.output_format), context.temp_allocator)
	if len(format) == 0 {
		if v, ok := os.lookup_env(constants.ENV_OUTPUT_FORMAT, context.temp_allocator); ok {
			format = strings.to_lower(v, context.temp_allocator)
		}
	}
	if format == "json" {
		print_json(res)
	} else {
		if len(res.err) > 0 && !res.ok {
			fmt.eprintln("nullray:", res.err)
		}
		if len(res.text) > 0 {
			fmt.println(res.text)
		}
		if len(res.plan_path) > 0 {
			if len(agent.plan_in_from_env(context.temp_allocator)) > 0 {
				fmt.eprintln("nullray: plan loaded", res.plan_path)
			} else {
				fmt.eprintln("nullray: plan saved", res.plan_path)
			}
		}
	}
	if cfg.print_usage || print_usage_from_env() {
		emit_usage(res, format == "json")
	}
}

@(private)
emit_usage :: proc(res: Result, json_already: bool) {
	if json_already {
		return
	}
	cost := "unknown"
	if res.session_usage.cost_known {
		cost = fmt.tprintf("%.6f", res.session_usage.cost_usd)
	} else if res.session_usage.total_tokens > 0 {
		cost = "unknown (provider omitted)"
	}
	fmt.eprintf(
		"nullray: usage turn=%d/%d/%d session=%d/%d/%d reasoning=%d chars=%d/%d cost=%s subagent_tok=%d\n",
		res.usage.prompt_tokens,
		res.usage.completion_tokens,
		res.usage.total_tokens,
		res.session_usage.prompt_tokens,
		res.session_usage.completion_tokens,
		res.session_usage.total_tokens,
		res.session_usage.reasoning_tokens,
		res.input_chars,
		res.peak_input_chars,
		cost,
		res.subagent_total_tokens,
	)
}

@(private)
print_json :: proc(res: Result) {
	esc_text := json_escape(res.text, context.temp_allocator)
	esc_err := json_escape(res.err, context.temp_allocator)
	esc_plan := json_escape(res.plan_path, context.temp_allocator)
	esc_mode := json_escape(res.mode, context.temp_allocator)
	esc_stopped := json_escape(res.stopped, context.temp_allocator)
	count, found := agent.parse_findings_trailer(res.text)
	items := agent.parse_findings_list(res.text, context.temp_allocator)
	findings_json := agent.findings_to_json(items, count, found, context.temp_allocator)
	cost_note := ""
	if !res.session_usage.cost_known && res.session_usage.total_tokens > 0 {
		cost_note = "provider omitted cost"
	}
	esc_cost_note := json_escape(cost_note, context.temp_allocator)
	fmt.printf(
		`{{"ok":%v,"mode":"%s","text":"%s","plan_path":"%s","stopped":"%s","err":"%s","exit_code":%d,"findings":%s,"cost_note":"%s","usage":{{"prompt_tokens":%d,"completion_tokens":%d,"total_tokens":%d,"reasoning_tokens":%d,"cost_usd":%.6f,"cost_known":%v,"input_chars":%d}},"session_usage":{{"turns":%d,"prompt_tokens":%d,"completion_tokens":%d,"total_tokens":%d,"reasoning_tokens":%d,"cost_usd":%.6f,"cost_known":%v,"peak_input_chars":%d,"subagent_total_tokens":%d}}}}`+"\n",
		res.ok,
		esc_mode,
		esc_text,
		esc_plan,
		esc_stopped,
		esc_err,
		res.exit_code,
		findings_json,
		esc_cost_note,
		res.usage.prompt_tokens,
		res.usage.completion_tokens,
		res.usage.total_tokens,
		res.usage.reasoning_tokens,
		res.usage.cost_usd,
		res.usage.cost_known,
		res.input_chars,
		res.usage_turns,
		res.session_usage.prompt_tokens,
		res.session_usage.completion_tokens,
		res.session_usage.total_tokens,
		res.session_usage.reasoning_tokens,
		res.session_usage.cost_usd,
		res.session_usage.cost_known,
		res.peak_input_chars,
		res.subagent_total_tokens,
	)
}

@(private)
json_escape :: proc(s: string, allocator := context.allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	for r in s {
		switch r {
		case '"':
			strings.write_string(&b, `\"`)
		case '\\':
			strings.write_string(&b, `\\`)
		case '\n':
			strings.write_string(&b, `\n`)
		case '\r':
			strings.write_string(&b, `\r`)
		case '\t':
			strings.write_string(&b, `\t`)
		case:
			strings.write_rune(&b, r)
		}
	}
	return strings.to_string(b)
}
