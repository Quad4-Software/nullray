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

	s: session.Session
	session.session_init(&s)
	defer session.session_destroy(&s)
	_ = session.session_apply_saved_model(&s, &reg)
	session.session_sticky_auto_provider(&s, &reg)
	provider.set_session(s.name)
	s.tools_registry = &tools_reg
	s.tools_enabled = session.tools_enabled_from_env()

	p := provider.registry_active(&reg)
	if p == nil || p.chat == nil {
		res.err = strings.clone("no provider")
		return res
	}

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
		session.session_ensure_plan_step_note(&s)
	}
	session.session_rebuild_system_prompt(&s)

	delete(res.mode)
	res.mode = strings.clone(agent.mode_string(s.agent_mode))

	hunt := agent.hunt_from_env()
	do_auto := agent.hunt_auto_twopass(hunt) && s.agent_mode == .Review
	if do_auto {
		agent.hunt_set_phase(.Explore)
		session.session_rebuild_system_prompt(&s)
	}

	session.session_push_user(&s, prompt)
	session.session_start_chat(&s, p)

	deadline := time.tick_now()
	timeout := time.Duration(timeout_sec) * time.Second
	ok_done, wait_err := wait_session_chat(&s, &rt, deadline, timeout, timeout_sec, &res)
	if len(wait_err) > 0 {
		return res
	}
	if !ok_done {
		res.err = strings.clone("job did not finish")
		return res
	}

	if len(s.status) >= 5 && s.status[:5] == "error" {
		res.err = strings.clone(s.status)
		return res
	}

	explore_text := ""
	if do_auto {
		explore_text = last_assistant_text(&s)
		agent.hunt_set_phase(.Oracle)
		// Shrink tool blobs and cap explore reply before the second billed pass.
		session.session_phase_reset_provider_window(&s)
		session.session_cap_last_assistant(&s, constants.MAX_HUNT_EXPLORE_CHARS)
		session.session_rebuild_system_prompt(&s)
		session.session_push_user(&s, agent.HUNT_ORACLE_FOLLOWUP)
		session.session_start_chat(&s, p)
		ok2, wait_err2 := wait_session_chat(&s, &rt, deadline, timeout, timeout_sec, &res)
		if len(wait_err2) > 0 {
			delete(explore_text)
			return res
		}
		if !ok2 {
			delete(explore_text)
			res.err = strings.clone("hunt oracle phase did not finish")
			return res
		}
		if len(s.status) >= 5 && s.status[:5] == "error" {
			delete(explore_text)
			res.err = strings.clone(s.status)
			return res
		}
	}

	text := last_assistant_text(&s)
	tool_only := false
	if len(text) == 0 {
		// Models often end on a tool-only turn with empty assistant content.
		if session_had_tool_activity(&s) {
			text = strings.clone("(ok: tools completed, no final assistant text)")
			tool_only = true
		} else {
			delete(explore_text)
			res.err = strings.clone("no assistant reply")
			return res
		}
	}
	if do_auto && len(explore_text) > 0 {
		combined := strings.concatenate(
			{explore_text, "\n\n--- hunt oracle ---\n\n", text},
			context.allocator,
		)
		delete(explore_text)
		delete(text)
		text = combined
	} else {
		delete(explore_text)
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
wait_session_chat :: proc(
	s: ^session.Session,
	rt: ^subagent.Runtime,
	deadline: time.Tick,
	timeout: time.Duration,
	timeout_sec: int,
	res: ^Result,
) -> (
	ok_done: bool,
	fatal: string,
) {
	for {
		_ = session.session_poll(s)
		if !s.busy {
			return true, ""
		}
		if time.tick_since(deadline) > timeout {
			session.session_request_cancel(s)
			for _ in 0 ..< 40 {
				_ = session.session_poll(s)
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
			text := last_assistant_text(s)
			if len(text) > 0 {
				delete(res.text)
				res.text = text
			}
			living := subagent.roster_living_count(&rt.roster)
			if living > 0 {
				fmt.eprintf("nullray: %d subagent(s) still running\n", living)
			}
			strict := false
			if v, ok := os.lookup_env(constants.ENV_PRINT_STRICT, context.temp_allocator); ok {
				switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
				case "1", "true", "yes", "on":
					strict = true
				}
			}
			if strict {
				if fail, reason := print_strict_fail(s, res^, living, false); fail {
					res.ok = false
					res.exit_code = 1
					fmt.eprintln("nullray:", reason)
					return false, "timeout"
				}
			}
			res.ok = false
			res.exit_code = 2
			return false, "timeout"
		}
		time.sleep(50 * time.Millisecond)
	}
}
