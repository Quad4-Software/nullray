// SPDX-License-Identifier: 0BSD
/*
Headless print-mode agent: one prompt, tools loop, no TUI.
*/

package run

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import "nullray:agent"
import "nullray:constants"
import "nullray:mcp"
import "nullray:provider"
import "nullray:session"
import "nullray:subagent"
import "nullray:tools"

Config :: struct {
	prompt:           string,
	output_format:    string,
	out_path:         string,
	plan_out:         string,
	bare:             bool,
	fail_on_findings: bool,
	timeout_sec:      int,
	print_strict:     bool,
	print_usage:      bool,
}

Result :: struct {
	ok:                   bool,
	text:                 string,
	plan_path:            string,
	stopped:              string,
	mode:                 string,
	err:                  string,
	exit_code:            int,
	usage:                provider.Usage,
	session_usage:        provider.Usage,
	input_chars:          int,
	peak_input_chars:     int,
	usage_turns:          int,
	subagent_total_tokens: int,
	tool_only:            bool,
}

result_destroy :: proc(r: ^Result) {
	delete(r.text)
	delete(r.plan_path)
	delete(r.stopped)
	delete(r.mode)
	delete(r.err)
	r^ = {}
}

run_print :: proc(cfg: Config) -> Result {
	res: Result
	res.mode = strings.clone(agent.mode_string(agent.mode_from_env()))
	res.exit_code = 2

	plan_in := agent.plan_in_from_env()
	defer delete(plan_in)
	plan_out := agent.plan_out_from_env(context.temp_allocator)
	if len(plan_in) > 0 && len(plan_out) > 0 {
		res.err = strings.clone("plan-in and plan-out cannot be used together")
		return res
	}

	plan_body := ""
	defer delete(plan_body)
	if len(plan_in) > 0 {
		mode_early := agent.mode_from_env()
		if mode_early != .Edit {
			res.err = strings.clone(
				fmt.tprintf("plan-in requires --mode edit (got %s)", agent.mode_string(mode_early)),
			)
			return res
		}
		body, perr := agent.load_plan_file(plan_in)
		if len(perr) > 0 {
			res.err = perr
			return res
		}
		plan_body = body
	}

	prompt := strings.trim_space(cfg.prompt)
	if len(prompt) == 0 {
		if len(plan_in) > 0 {
			prompt = agent.DEFAULT_PLAN_APPLY_PROMPT
		} else {
			res.err = strings.clone("print mode needs a prompt (args, --message-file, or stdin)")
			return res
		}
	}

	agent.apply_auto_mode()

	perms := tools.perms_from_env()
	mode := agent.mode_from_env()
	if len(plan_in) > 0 {
		mode = .Edit
	}
	if mode == .Edit && perms == .Ask {
		res.err = strings.clone("print mode with edit needs --perms allow or --perms yolo (no /allow)")
		return res
	}

	timeout_sec := cfg.timeout_sec
	if timeout_sec <= 0 {
		timeout_sec = print_timeout_from_env()
	}

	tools_reg: tools.Registry
	tools.registry_init(&tools_reg)
	defer tools.registry_destroy(&tools_reg)

	mcp_reg: mcp.Registry
	mcp.registry_init(&mcp_reg, &tools_reg)
	defer mcp.registry_destroy(&mcp_reg)
	if !cfg.bare && !agent.bare_from_env() {
		mcp.mcp_autoload(&mcp_reg)
	}

	reg: provider.Registry
	provider.registry_init(&reg)
	defer provider.registry_destroy(&reg)

	p := provider.registry_active(&reg)
	if p == nil || p.chat == nil {
		res.err = strings.clone("no provider")
		return res
	}

	s: session.Session
	session.session_init(&s)
	defer session.session_destroy(&s)
	s.tools_registry = &tools_reg
	s.tools_enabled = true

	rt: subagent.Runtime
	subagent.runtime_init(&rt, s.name, &tools_reg)
	subagent.runtime_set_session(&rt, s.session_path, s.persist)
	subagent.runtime_set(&rt)
	defer {
		subagent.runtime_set(nil)
		subagent.runtime_destroy(&rt)
	}
	agent.register_subagent_runner()
	subagent.runtime_set_provider(&rt, p)
	delete(rt.main_model)
	rt.main_model = strings.clone(p.default_model)
	tools.register_subagent_tools(&tools_reg, subagent.runtime_enabled(&rt))

	if ephemeral_forced() {
		s.persist = false
	}
	if agent.auto_from_env() {
		s.agent_mode = .Edit
		session.session_sync_mode_env(&s)
	}
	if len(plan_in) > 0 {
		if serr := session.session_seed_plan(&s, plan_in, plan_body); len(serr) > 0 {
			res.err = strings.clone(serr)
			return res
		}
		s.plan_contract_ok = true
		session.session_set_mode(&s, .Edit)
	}
	session.session_rebuild_system_prompt(&s)

	delete(res.mode)
	res.mode = strings.clone(agent.mode_string(s.agent_mode))

	session.session_push_user(&s, prompt)
	session.session_start_chat(&s, p)

	deadline := time.tick_now()
	timeout := time.Duration(timeout_sec) * time.Second
	ok_done := false
	for {
		_ = session.session_poll(&s)
		if !s.busy {
			ok_done = true
			break
		}
		if time.tick_since(deadline) > timeout {
			session.session_request_cancel(&s)
			for _ in 0 ..< 40 {
				_ = session.session_poll(&s)
				if !s.busy {
					break
				}
				time.sleep(50 * time.Millisecond)
			}
			delete(res.err)
			res.err = strings.clone(fmt.tprintf("timed out after %d seconds", timeout_sec))
			delete(res.stopped)
			res.stopped = strings.clone("timeout")
			res.usage = s.last_usage
			res.session_usage = s.session_usage
			res.input_chars = s.last_input_chars
			res.peak_input_chars = s.peak_input_chars
			res.usage_turns = s.usage_turns
			res.subagent_total_tokens = s.subagent_total_tokens
			text := last_assistant_text(&s)
			if len(text) > 0 {
				delete(res.text)
				res.text = text
			}
			living := subagent.roster_living_count(&rt.roster)
			if living > 0 {
				fmt.eprintf("nullray: %d subagent(s) still running\n", living)
			}
			strict := cfg.print_strict || print_strict_from_env()
			if strict {
				if fail, reason := print_strict_fail(&s, res, living, false); fail {
					res.ok = false
					res.exit_code = 1
					fmt.eprintln("nullray:", reason)
					return res
				}
			}
			res.ok = false
			res.exit_code = 2
			return res
		}
		time.sleep(50 * time.Millisecond)
	}

	if !ok_done {
		res.err = strings.clone("job did not finish")
		return res
	}

	if len(s.status) >= 5 && s.status[:5] == "error" {
		res.err = strings.clone(s.status)
		return res
	}

	text := last_assistant_text(&s)
	tool_only := false
	if len(text) == 0 {
		// Models often end on a tool-only turn with empty assistant content.
		if session_had_tool_activity(&s) {
			text = strings.clone("(ok: tools completed, no final assistant text)")
			tool_only = true
		} else {
			res.err = strings.clone("no assistant reply")
			return res
		}
	}
	res.text = text
	res.tool_only = tool_only
	res.usage = s.last_usage
	res.session_usage = s.session_usage
	res.input_chars = s.last_input_chars
	res.peak_input_chars = s.peak_input_chars
	res.usage_turns = s.usage_turns
	res.subagent_total_tokens = s.subagent_total_tokens
	stopped := s.last_stopped
	if len(stopped) == 0 {
		stopped = "done"
	}
	delete(res.stopped)
	res.stopped = strings.clone(stopped)
	res.ok = true
	res.exit_code = 0

	if len(s.last_plan_path) > 0 {
		res.plan_path = strings.clone(s.last_plan_path)
	}

	living := subagent.roster_living_count(&rt.roster)
	if living > 0 {
		fmt.eprintf("nullray: %d subagent(s) still running\n", living)
	}

	strict := cfg.print_strict || print_strict_from_env()
	if strict {
		if fail, reason := print_strict_fail(&s, res, living, tool_only); fail {
			res.ok = false
			res.exit_code = 1
			if len(res.err) == 0 {
				res.err = strings.clone(reason)
			}
			fmt.eprintln("nullray:", reason)
		}
	}

	if len(cfg.out_path) > 0 && s.agent_mode != .Plan {
		if werr := write_text_file(cfg.out_path, res.text); len(werr) > 0 {
			delete(res.err)
			res.err = werr
			res.ok = false
			res.exit_code = 2
			return res
		}
	}

	if s.agent_mode == .Review && (cfg.fail_on_findings || agent.fail_on_findings_from_env()) {
		n, found := agent.parse_findings_trailer(res.text)
		if found && n > 0 {
			res.exit_code = 1
		} else if !found {
			fmt.eprintln("nullray: warning: review reply missing FINDINGS trailer")
		}
	}

	return res
}

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
	switch res.stopped {
	case "max_steps", "loop", "timeout":
		return true, fmt.tprintf("print-strict: stopped with %s", res.stopped)
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
	fmt.printf(
		`{{"ok":%v,"mode":"%s","text":"%s","plan_path":"%s","stopped":"%s","err":"%s","exit_code":%d,"usage":{{"prompt_tokens":%d,"completion_tokens":%d,"total_tokens":%d,"reasoning_tokens":%d,"cost_usd":%.6f,"cost_known":%v,"input_chars":%d}},"session_usage":{{"turns":%d,"prompt_tokens":%d,"completion_tokens":%d,"total_tokens":%d,"reasoning_tokens":%d,"cost_usd":%.6f,"cost_known":%v,"peak_input_chars":%d,"subagent_total_tokens":%d}}}}`+"\n",
		res.ok,
		esc_mode,
		esc_text,
		esc_plan,
		esc_stopped,
		esc_err,
		res.exit_code,
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

@(private)
last_assistant_text :: proc(s: ^session.Session, allocator := context.allocator) -> string {
	for i := len(s.messages) - 1; i >= 0; i -= 1 {
		if s.messages[i].role == .Assistant && len(s.messages[i].content) > 0 {
			return strings.clone(s.messages[i].content, allocator)
		}
	}
	return ""
}

@(private)
session_had_tool_activity :: proc(s: ^session.Session) -> bool {
	for m in s.messages {
		if m.role == .Tool {
			return true
		}
		if m.role == .Assistant && len(m.tool_calls) > 0 {
			return true
		}
	}
	return false
}

@(private)
write_text_file :: proc(path, text: string, allocator := context.allocator) -> string {
	if merr := agent.ensure_parent_dirs(path); len(merr) > 0 {
		return strings.clone(merr, allocator)
	}
	if werr := os.write_entire_file(path, transmute([]u8)text); werr != nil {
		return fmt.aprintf("write %s failed: %v", path, werr, allocator = allocator)
	}
	return ""
}

@(private)
ephemeral_forced :: proc() -> bool {
	if v, ok := os.lookup_env(constants.ENV_EPHEMERAL, context.temp_allocator); ok {
		switch strings.to_lower(v, context.temp_allocator) {
		case "1", "true", "yes", "on":
			return true
		}
	}
	return false
}

print_timeout_from_env :: proc() -> int {
	if v, ok := os.lookup_env(constants.ENV_PRINT_TIMEOUT, context.temp_allocator); ok && len(v) > 0 {
		n, okp := parse_positive_int(v)
		if okp {
			return n
		}
	}
	return constants.DEFAULT_PRINT_TIMEOUT_SEC
}

@(private)
parse_positive_int :: proc(s: string) -> (int, bool) {
	n := 0
	if len(s) == 0 {
		return 0, false
	}
	for c in s {
		if c < '0' || c > '9' {
			return 0, false
		}
		n = n * 10 + int(c - '0')
	}
	return n, n > 0
}

build_prompt :: proc(positional: string, message_file: string, read_stdin: bool, allocator := context.allocator) -> (string, string) {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	if len(positional) > 0 {
		strings.write_string(&b, positional)
	}
	if len(message_file) > 0 {
		data, err := os.read_entire_file(message_file, context.temp_allocator)
		if err != nil {
			return "", fmt.aprintf("read --message-file: %v", err, allocator = allocator)
		}
		if strings.builder_len(b) > 0 {
			strings.write_string(&b, "\n\n")
		}
		strings.write_string(&b, string(data))
	}
	if read_stdin {
		data, ok := read_all_stdin(context.temp_allocator)
		if ok && len(data) > 0 {
			if strings.builder_len(b) > 0 {
				strings.write_string(&b, "\n\n")
			}
			strings.write_string(&b, data)
		}
	}
	return strings.to_string(b), ""
}
