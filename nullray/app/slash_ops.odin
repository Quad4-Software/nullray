// SPDX-License-Identifier: 0BSD
/*
Slash commands: status, sandbox, verify, control flow.
*/

package app

import "core:fmt"
import "core:os"
import "core:strings"
import "nullray:agent"
import "nullray:constants"
import "nullray:hooks"
import "nullray:provider"
import "nullray:sandbox"
import "nullray:session"
import "nullray:store"
import "nullray:tools"

slash_cmd_status :: proc(a: ^App, args: string) {
	_ = args
	plan := a.session.last_plan_path
	if len(plan) == 0 {
		plan = "(none)"
	}
	vcmd, voff := agent.resolve_verify_command(a.session.plan_verify, context.temp_allocator)
	verify := vcmd
	if voff {
		verify = "off"
	} else if len(verify) == 0 {
		verify = "(default)"
	}
	sandbox_applied := false
	ops_line := "ops=off"
	if sstate := sandbox.state(); sstate != nil {
		sandbox_applied = sstate.applied
		if len(sstate.ops_label) > 0 {
			ops_line = fmt.tprintf("ops=%s", sstate.ops_label)
		}
	}
	char_budget := session.compact_chars_from_env()
	cost_line := "cost=unknown"
	if a.hide_sensitive {
		cost_line = "cost=hidden"
	} else if a.session.session_usage.cost_known {
		cost_line = fmt.tprintf("cost=$%.6f", a.session.session_usage.cost_usd)
	}
	stopped := a.session.last_stopped
	if len(stopped) == 0 {
		stopped = "-"
	}
	body := fmt.tprintf(
		"mode=%s\nhunt=%s\nsandbox_applied=%v\n%s\nask_simple=%v\nplan_ok=%v\nverify=%s\nfails=%d\nchars=%d/%d\npeak=%d\ntok=%d/%d\n%s\nstopped=%s\nplan=%s\nview_auto=%v",
		agent.mode_string(a.session.agent_mode),
		agent.hunt_profile_string(agent.hunt_from_env()),
		sandbox_applied,
		ops_line,
		agent.ask_simple_from_env(),
		a.session.plan_contract_ok,
		verify,
		a.session.verify_fail_count,
		a.session.last_input_chars,
		char_budget,
		a.session.peak_input_chars,
		a.session.last_usage.total_tokens,
		a.session.session_usage.total_tokens,
		cost_line,
		stopped,
		plan,
		a.view_auto,
	)
	delete(a.status_body)
	a.status_body = strings.clone(body)
	a.status_scroll = 0
	a.show_status = true
	app_mark_dirty(a)
}

slash_cmd_ops :: proc(a: ^App, args: string) {
	_ = args
	cfg := sandbox.config_from_env()
	defer sandbox.config_destroy(&cfg)
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	fmt.sbprintf(&b, "%s", sandbox.ops_summary_line(cfg, context.temp_allocator))
	if sstate := sandbox.state(); sstate != nil {
		fmt.sbprintf(&b, " applied=%v", sstate.applied)
		if len(sstate.allow_sock) > 0 {
			fmt.sbprintf(&b, " sock=%s", strings.join(sstate.allow_sock[:], ",", context.temp_allocator))
		}
	}
	if len(cfg.extra_rw) > 0 {
		fmt.sbprintf(&b, " rw=%s", strings.join(cfg.extra_rw[:], ",", context.temp_allocator))
	}
	session.session_set_status(&a.session, strings.to_string(b))
}

slash_cmd_usage :: proc(a: ^App, args: string) {
	rest := strings.trim_space(args)
	lower := strings.to_lower(rest, context.temp_allocator)
	switch {
	case lower == "json":
		js := session.session_usage_summary_json(&a.session)
		session.session_push_assistant(&a.session, js)
		delete(js)
		session.session_set_status(&a.session, "usage json")
	case strings.has_prefix(lower, "export"):
		path := strings.trim_space(rest[len("export"):])
		if len(path) == 0 {
			session.session_set_status(&a.session, "usage: /usage export PATH")
			return
		}
		ok, err := store.export_usage_summary(a.session.session_path, path)
		if !ok {
			session.session_set_status(&a.session, err)
			delete(err)
			return
		}
		session.session_set_status(&a.session, fmt.tprintf("usage exported %s", path))
	case:
		txt := session.session_usage_summary_text(&a.session, a.hide_sensitive)
		session.session_push_assistant(&a.session, txt)
		delete(txt)
		session.session_set_status(&a.session, "usage")
	}
}

slash_cmd_verify :: proc(a: ^App, args: string) {
	rest := strings.trim_space(args)
	if len(rest) == 0 {
		v, off := agent.verify_command_from_env(context.temp_allocator)
		if off {
			session.session_set_status(&a.session, "verify off (default). /verify on or /verify make test")
			return
		}
		if len(v) == 0 {
			resolved, _ := agent.resolve_verify_command(a.session.plan_verify, context.temp_allocator)
			if len(resolved) > 0 {
				session.session_set_status(&a.session, fmt.tprintf("verify on -> %s", resolved))
			} else {
				session.session_set_status(&a.session, "verify on (plan/AGENTS/make test)")
			}
			return
		}
		session.session_set_status(&a.session, fmt.tprintf("verify %s", v))
		return
	}
	lower := strings.to_lower(rest, context.temp_allocator)
	switch lower {
	case "off", "0", "false", "no":
		os.set_env(constants.ENV_VERIFY, "0")
		session.session_set_status(&a.session, "verify off")
	case "on", "1", "true", "yes":
		os.set_env(constants.ENV_VERIFY, "1")
		resolved, _ := agent.resolve_verify_command(a.session.plan_verify, context.temp_allocator)
		if len(resolved) > 0 {
			session.session_set_status(&a.session, fmt.tprintf("verify on -> %s", resolved))
		} else {
			session.session_set_status(&a.session, "verify on")
		}
	case:
		os.set_env(constants.ENV_VERIFY, rest)
		session.session_set_status(&a.session, fmt.tprintf("verify %s", rest))
	}
}

slash_cmd_perms :: proc(a: ^App, args: string) {
	rest := strings.trim_space(args)
	if len(rest) == 0 {
		session.session_set_status(
			&a.session,
			fmt.tprintf("perms %s (ask|allow|yolo)", tools.perms_string(tools.perms_from_env())),
		)
		return
	}
	p, ok := tools.perms_from_string(rest)
	if !ok {
		session.session_set_status(&a.session, "usage: /perms ask|allow|yolo")
		return
	}
	os.set_env(constants.ENV_PERMS, tools.perms_string(p))
	if p == .Yolo {
		os.set_env(constants.ENV_SHELL_CONFIRM, "0")
		os.set_env(constants.ENV_AUTONOMY, "1")
		os.set_env(constants.ENV_GATE, "3")
	} else if p == .Ask {
		os.unset_env(constants.ENV_AUTONOMY)
		os.set_env(constants.ENV_SHELL_CONFIRM, "1")
		// Shell-confirm UX stays at gate 2. Use /gate ask for read-only.
		os.set_env(constants.ENV_GATE, "2")
	} else {
		os.unset_env(constants.ENV_AUTONOMY)
		os.unset_env(constants.ENV_SHELL_CONFIRM)
		os.set_env(constants.ENV_GATE, "2")
	}
	session.session_set_status(&a.session, fmt.tprintf("perms %s gate %s", tools.perms_string(p), tools.gate_string(tools.gate_from_env())))
}

slash_cmd_quirks :: proc(a: ^App, args: string) {
	_ = args
	model := a.session.model
	p := provider.registry_active(&a.registry)
	if p != nil && len(p.default_model) > 0 && len(model) == 0 {
		model = p.default_model
	}
	body := provider.quirks_active_labels(model, context.temp_allocator)
	session.session_set_status(&a.session, body)
}

slash_cmd_gate :: proc(a: ^App, args: string) {
	rest := strings.trim_space(args)
	if len(rest) == 0 {
		session.session_set_status(
			&a.session,
			fmt.tprintf("gate %s (0 read | 1 write | 2 shell | 3 destructive)", tools.gate_label(tools.gate_from_env())),
		)
		return
	}
	g, ok := tools.gate_parse(rest)
	if !ok {
		session.session_set_status(&a.session, "usage: /gate 0..3|ask|allow|yolo")
		return
	}
	os.set_env(constants.ENV_GATE, tools.gate_string(g))
	switch g {
	case 0:
		os.set_env(constants.ENV_PERMS, "ask")
		os.set_env(constants.ENV_SHELL_CONFIRM, "1")
		os.unset_env(constants.ENV_AUTONOMY)
	case 1, 2:
		os.set_env(constants.ENV_PERMS, "allow")
		os.unset_env(constants.ENV_SHELL_CONFIRM)
		os.unset_env(constants.ENV_AUTONOMY)
	case 3:
		os.set_env(constants.ENV_PERMS, "yolo")
		os.set_env(constants.ENV_SHELL_CONFIRM, "0")
		os.set_env(constants.ENV_AUTONOMY, "1")
	}
	session.session_set_status(&a.session, fmt.tprintf("gate %s", tools.gate_label(g)))
}

slash_cmd_hooks :: proc(a: ^App, args: string) {
	rest := strings.trim_space(args)
	if rest == "trust" || rest == "approve" {
		_ = hooks.hooks_trust_workspace()
		session.session_set_status(&a.session, "workspace hooks trusted")
		return
	}
	path := hooks.hooks_workspace_source(context.temp_allocator)
	session.session_set_status(&a.session, fmt.tprintf("hooks: %s · /hooks trust to re-approve", path))
}

slash_cmd_pause :: proc(a: ^App, args: string) {
	_ = args
	if a.session.busy {
		session.session_request_pause(&a.session)
	} else {
		session.session_set_status(&a.session, "not running")
	}
}

slash_cmd_stop :: proc(a: ^App, args: string) {
	_ = args
	if a.session.busy {
		session.session_request_cancel(&a.session)
	} else {
		session.session_set_status(&a.session, "not running")
	}
}

slash_cmd_continue :: proc(a: ^App, args: string) {
	extra := strings.trim_space(args)
	p := provider.registry_active(&a.registry)
	session.session_resume(&a.session, p, extra)
	app_mark_dirty(a)
}

slash_cmd_retry :: proc(a: ^App, args: string) {
	_ = args
	if a.session.busy {
		session.session_set_status(&a.session, "busy · stop first or wait")
		return
	}
	p := provider.registry_active(&a.registry)
	if p == nil {
		session.session_set_status(&a.session, "no provider")
		return
	}
	app_reveal_reset(a)
	if session.session_retry_last(&a.session, p) {
		app_toast_ok(a, "retrying last turn")
		session.session_set_status(&a.session, "retrying...")
	} else {
		app_toast(a, "nothing to retry", .Warn)
		session.session_set_status(&a.session, "nothing to retry")
	}
	app_mark_dirty(a)
}

slash_cmd_auto :: proc(a: ^App, args: string) {
	rest := strings.trim_space(args)
	if rest == "on" {
		os.set_env(constants.ENV_AUTO, "1")
		agent.apply_auto_mode()
		session.session_set_mode(&a.session, .Edit)
		session.session_set_status(&a.session, "auto on (edit + yolo)")
		return
	}
	if rest == "off" {
		os.unset_env(constants.ENV_AUTO)
		os.unset_env(constants.ENV_AUTONOMY)
		os.set_env(constants.ENV_PERMS, "allow")
		session.session_set_status(&a.session, "auto off")
		return
	}
	on := agent.auto_from_env()
	session.session_set_status(&a.session, fmt.tprintf("auto %s (use /auto on|off)", on ? "on" : "off"))
}

slash_cmd_secrets :: proc(a: ^App, args: string) {
	path := strings.trim_space(args)
	if len(path) == 0 {
		cur, ok := os.lookup_env(constants.ENV_SECRETS_ALLOW, context.temp_allocator)
		if !ok || len(cur) == 0 {
			cur = "(none)"
		}
		session.session_set_status(&a.session, fmt.tprintf("NULLRAY_SECRETS_ALLOW=%s", cur))
		return
	}
	cur, _ := os.lookup_env(constants.ENV_SECRETS_ALLOW, context.temp_allocator)
	if len(cur) > 0 {
		os.set_env(constants.ENV_SECRETS_ALLOW, fmt.tprintf("%s,%s", cur, path))
	} else {
		os.set_env(constants.ENV_SECRETS_ALLOW, path)
	}
	session.session_set_status(&a.session, fmt.tprintf("secrets allow += %s", path))
}

slash_cmd_hide :: proc(a: ^App, args: string) {
	rest := strings.trim_space(args)
	switch strings.to_lower(rest, context.temp_allocator) {
	case "on", "1", "true", "yes", "hide":
		app_set_hide_sensitive(a, true)
		session.session_set_status(&a.session, "hide on (balances hidden)")
	case "off", "0", "false", "no", "show":
		app_set_hide_sensitive(a, false)
		session.session_set_status(&a.session, "hide off")
	case "":
		app_set_hide_sensitive(a, !a.hide_sensitive)
		if a.hide_sensitive {
			session.session_set_status(&a.session, "hide on (balances hidden)")
		} else {
			session.session_set_status(&a.session, "hide off")
		}
	case:
		session.session_set_status(&a.session, "usage: /hide on|off")
	}
}

slash_cmd_review :: proc(a: ^App, args: string) {
	rest := strings.trim_space(args)
	if rest == "on" {
		os.set_env(constants.ENV_REVIEW, "on")
		session.session_set_status(&a.session, "review on")
		return
	}
	if rest == "off" {
		os.set_env(constants.ENV_REVIEW, "off")
		session.session_set_status(&a.session, "review off")
		return
	}
	on := agent.review_enabled_from_env()
	session.session_set_status(&a.session, fmt.tprintf("review %s (NULLRAY_REVIEW_MODEL optional)", on ? "on" : "off"))
}

slash_cmd_allow :: proc(a: ^App, args: string) {
	_ = args
	cmd, ok := tools.shell_allow_once()
	if !ok {
		session.session_set_status(&a.session, "no pending shell command")
		return
	}
	session.session_set_status(&a.session, fmt.tprintf("allowed once: %s (agent may retry)", cmd))
	delete(cmd)
}

slash_cmd_deny :: proc(a: ^App, args: string) {
	_ = args
	tools.shell_deny_pending()
	session.session_set_status(&a.session, "pending shell denied")
}
