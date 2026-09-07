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
import "nullray:tools"

Config :: struct {
	prompt:           string,
	output_format:    string,
	out_path:         string,
	plan_out:         string,
	bare:             bool,
	fail_on_findings: bool,
	timeout_sec:      int,
}

Result :: struct {
	ok:         bool,
	text:       string,
	plan_path:  string,
	stopped:    string,
	mode:       string,
	err:        string,
	exit_code:  int,
	usage:      provider.Usage,
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

	prompt := strings.trim_space(cfg.prompt)
	if len(prompt) == 0 {
		res.err = strings.clone("print mode needs a prompt (args, --message-file, or stdin)")
		return res
	}

	agent.apply_auto_mode()

	perms := tools.perms_from_env()
	mode := agent.mode_from_env()
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
	if ephemeral_forced() {
		s.persist = false
	}
	if agent.auto_from_env() {
		s.agent_mode = .Edit
		session.session_sync_mode_env(&s)
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
			res.err = strings.clone(fmt.tprintf("timed out after %d seconds", timeout_sec))
			res.stopped = strings.clone("timeout")
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
	if len(text) == 0 {
		res.err = strings.clone("no assistant reply")
		return res
	}
	res.text = text
	res.usage = s.last_usage
	res.stopped = strings.clone("done")
	res.ok = true
	res.exit_code = 0

	if len(s.last_plan_path) > 0 {
		res.plan_path = strings.clone(s.last_plan_path)
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

emit_result :: proc(cfg: Config, res: Result) {
	format := strings.to_lower(strings.trim_space(cfg.output_format), context.temp_allocator)
	if len(format) == 0 {
		if v, ok := os.lookup_env(constants.ENV_OUTPUT_FORMAT, context.temp_allocator); ok {
			format = strings.to_lower(v, context.temp_allocator)
		}
	}
	if format == "json" {
		print_json(res)
		return
	}
	if len(res.err) > 0 && !res.ok {
		fmt.eprintln("nullray:", res.err)
	}
	if len(res.text) > 0 {
		fmt.println(res.text)
	}
	if len(res.plan_path) > 0 {
		fmt.eprintln("nullray: plan saved", res.plan_path)
	}
}

@(private)
print_json :: proc(res: Result) {
	esc_text := json_escape(res.text, context.temp_allocator)
	esc_err := json_escape(res.err, context.temp_allocator)
	esc_plan := json_escape(res.plan_path, context.temp_allocator)
	esc_mode := json_escape(res.mode, context.temp_allocator)
	esc_stopped := json_escape(res.stopped, context.temp_allocator)
	fmt.printf(
		`{"ok":%v,"mode":"%s","text":"%s","plan_path":"%s","stopped":"%s","err":"%s","exit_code":%d,"usage":{"prompt_tokens":%d,"completion_tokens":%d,"total_tokens":%d}}`+"\n",
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
