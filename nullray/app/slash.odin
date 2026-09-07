// SPDX-License-Identifier: 0BSD
/*
Slash command handlers and dispatch for the TUI.
*/

package app

import "core:fmt"
import "core:os"
import "core:strings"
import "nullray:agent"
import "nullray:config"
import "nullray:constants"
import "nullray:provider"
import "nullray:sandbox"
import "nullray:session"
import "nullray:skills"
import "nullray:store"
import "nullray:subagent"
import "nullray:tools"
import "nullray:ui"

app_handle_slash :: proc(a: ^App, text: string) -> bool {
	t := strings.trim_space(text)
	if !strings.has_prefix(t, "/") {
		return false
	}
	body := t[1:]
	name := body
	args := ""
	if sp := strings.index_byte(body, ' '); sp >= 0 {
		name = body[:sp]
		args = strings.trim_space(body[sp + 1:])
	}
	if len(name) == 0 {
		return false
	}
	cmd, ok := slash_find(name)
	if !ok || cmd.run == nil {
		session.session_set_status(&a.session, fmt.tprintf("unknown command: /%s · type ?", name))
		return true
	}
	cmd.run(a, args)
	return true
}

slash_cmd_help :: proc(a: ^App, args: string) {
	_ = args
	app_toggle_help(a)
}

slash_cmd_keys :: proc(a: ^App, args: string) {
	_ = args
	help := config.binds_help_text(a.binds, a.keys_preset)
	session.session_push_assistant(&a.session, help)
	delete(help)
	session.session_set_status(&a.session, "keys")
}

slash_cmd_setup :: proc(a: ^App, args: string) {
	_ = args
	app_setup_open(a, false)
}

slash_cmd_themes :: proc(a: ^App, args: string) {
	_ = args
	names := ui.theme_names()
	b: strings.Builder
	strings.builder_init(&b)
	strings.write_string(&b, "themes: ")
	for n, i in names {
		if i > 0 {
			strings.write_string(&b, ", ")
		}
		strings.write_string(&b, n)
	}
	fmt.sbprintf(&b, "\ncurrent: %s", ui.theme().name)
	out := strings.to_string(b)
	session.session_push_assistant(&a.session, out)
	delete(out)
	session.session_set_status(&a.session, "themes")
}

slash_cmd_skills :: proc(a: ^App, args: string) {
	id := strings.trim_space(args)
	if len(id) == 0 {
		list := skills.skills_list_text()
		session.session_push_assistant(&a.session, list)
		delete(list)
		session.session_set_status(&a.session, "skills")
		return
	}
	text, ok := skills.skills_show_text(id)
	if !ok {
		session.session_set_status(&a.session, fmt.tprintf("unknown skill: %s · type /skills", id))
		return
	}
	session.session_push_assistant(&a.session, text)
	delete(text)
	session.session_set_status(&a.session, fmt.tprintf("skill %s", id))
}

slash_cmd_theme :: proc(a: ^App, args: string) {
	name := strings.trim_space(args)
	if len(name) == 0 {
		session.session_set_status(&a.session, fmt.tprintf("theme %s", ui.theme().name))
		return
	}
	if !ui.theme_exists(name) {
		session.session_set_status(&a.session, "usage: /theme ink|ember|moss|slate|rose|mono|dusk")
		return
	}
	ui.theme_set(ui.theme_by_name(name))
	if a.loop != nil {
		a.loop.theme = ui.theme()
		ui.loop_request_full_redraw(a.loop)
	}
	session.session_set_status(&a.session, fmt.tprintf("theme %s", ui.theme().name))
	app_mark_dirty(a)
}

slash_cmd_compact :: proc(a: ^App, args: string) {
	_ = args
	p := provider.registry_active(&a.registry)
	_ = session.session_compact_with_provider(&a.session, p)
}

slash_cmd_tools :: proc(a: ^App, args: string) {
	_ = args
	a.session.tools_enabled = !a.session.tools_enabled
	mode := "tools on"
	if !a.session.tools_enabled {
		mode = "tools off"
	}
	session.session_set_status(&a.session, mode)
}

slash_cmd_reasoning :: proc(a: ^App, args: string) {
	rest := strings.trim_space(args)
	if len(rest) == 0 {
		session.session_set_status(&a.session, fmt.tprintf("reasoning %s (none|minimal|low|medium|high|xhigh|max)", a.session.reasoning_effort))
		return
	}
	effort, ok := session.normalize_reasoning_effort(rest)
	if !ok {
		session.session_set_status(&a.session, "usage: /reasoning none|minimal|low|medium|high|xhigh|max")
		return
	}
	delete(a.session.reasoning_effort)
	a.session.reasoning_effort = strings.clone(effort)
	session.session_set_status(&a.session, fmt.tprintf("reasoning %s", a.session.reasoning_effort))
}

slash_cmd_sessions :: proc(a: ^App, args: string) {
	_ = args
	list := session.session_list_text()
	session.session_push_assistant(&a.session, list)
	delete(list)
	session.session_set_status(&a.session, "sessions")
}

slash_cmd_search :: proc(a: ^App, args: string) {
	q := strings.trim_space(args)
	if len(q) == 0 {
		session.session_set_status(&a.session, "usage: /search query")
		return
	}
	list := session.session_search_text(q)
	session.session_push_assistant(&a.session, list)
	delete(list)
	session.session_set_status(&a.session, "search")
}

slash_cmd_resume :: proc(a: ^App, args: string) {
	name := strings.trim_space(args)
	if len(name) == 0 {
		session.session_set_status(&a.session, "usage: /resume name")
		return
	}
	if session.session_switch(&a.session, name) {
		_ = session.session_apply_saved_model(&a.session, &a.registry)
		app_refresh_credits(a)
		session.session_set_status(&a.session, fmt.tprintf("resumed %s", a.session.name))
	} else {
		session.session_set_status(&a.session, fmt.tprintf("no session %s", name))
	}
}

slash_cmd_name :: proc(a: ^App, args: string) {
	name := strings.trim_space(args)
	if len(name) == 0 {
		session.session_set_status(&a.session, "usage: /name name")
		return
	}
	_ = session.session_rename(&a.session, name)
}

slash_cmd_new :: proc(a: ^App, args: string) {
	name := strings.trim_space(args)
	if len(name) == 0 {
		name = "session"
	}
	_ = session.session_new(&a.session, name)
}

slash_cmd_fork :: proc(a: ^App, args: string) {
	name := strings.trim_space(args)
	if len(name) == 0 {
		session.session_set_status(&a.session, "usage: /fork name")
		return
	}
	_ = session.session_fork(&a.session, name)
}

slash_cmd_delete :: proc(a: ^App, args: string) {
	name := strings.trim_space(args)
	if len(name) == 0 {
		session.session_set_status(&a.session, "usage: /delete name")
		return
	}
	safe := store.sanitize_name(name)
	if safe == a.session.name {
		session.session_set_status(&a.session, "switch or /new before deleting the open session")
		return
	}
	ok, err := store.delete_session(safe)
	if !ok {
		session.session_set_status(&a.session, err)
		return
	}
	session.session_set_status(&a.session, fmt.tprintf("deleted %s", safe))
}

slash_cmd_ephemeral :: proc(a: ^App, args: string) {
	rest := strings.trim_space(args)
	if rest == "off" {
		session.session_set_ephemeral(&a.session, false)
		return
	}
	session.session_set_ephemeral(&a.session, true)
}

slash_cmd_group :: proc(a: ^App, args: string) {
	name := strings.trim_space(args)
	if len(name) == 0 {
		g := a.session.group
		if len(g) == 0 {
			g = "(none)"
		}
		session.session_set_status(&a.session, fmt.tprintf("group %s", g))
		return
	}
	session.session_set_group(&a.session, name)
}

slash_cmd_mode :: proc(a: ^App, args: string) {
	rest := strings.trim_space(args)
	if len(rest) == 0 {
		session.session_set_status(&a.session, fmt.tprintf("mode %s (ask|plan|review|edit)", agent.mode_string(a.session.agent_mode)))
		return
	}
	m, ok := agent.mode_from_string(rest)
	if !ok {
		session.session_set_status(&a.session, "usage: /mode ask|plan|review|edit")
		return
	}
	session.session_set_mode(&a.session, m)
}

slash_cmd_model :: proc(a: ^App, args: string) {
	rest := strings.trim_space(args)
	p := provider.registry_active(&a.registry)
	if len(rest) == 0 {
		lock := subagent.policy_is_locked() || a.subagents.model_locked
		model := p != nil ? p.default_model : a.session.model
		session.session_set_status(&a.session, fmt.tprintf("model %s lock=%s", model, lock ? "on" : "off"))
		return
	}
	low := strings.to_lower(rest, context.temp_allocator)
	if low == "lock" {
		subagent.policy_set_lock(true)
		a.subagents.model_locked = true
		if p != nil {
			delete(a.subagents.main_model)
			a.subagents.main_model = strings.clone(p.default_model)
		}
		session.session_set_status(&a.session, "model locked")
		return
	}
	if low == "unlock" {
		subagent.policy_set_lock(false)
		a.subagents.model_locked = false
		session.session_set_status(&a.session, "model unlocked")
		return
	}
	if subagent.policy_is_locked() || a.subagents.model_locked {
		session.session_set_status(&a.session, "model locked (use /model unlock)")
		return
	}
	resolved, err := subagent.policy_resolve("main", rest, p != nil ? p.default_model : "", "", context.temp_allocator)
	if err != "" {
		session.session_set_status(&a.session, err)
		return
	}
	if p != nil {
		delete(p.default_model)
		p.default_model = strings.clone(resolved)
		session.session_remember_model(&a.session, p.id, p.default_model)
	}
	delete(a.subagents.main_model)
	a.subagents.main_model = strings.clone(resolved)
	subagent.runtime_set_provider(&a.subagents, p)
	session.session_set_status(&a.session, fmt.tprintf("model %s", resolved))
}

slash_cmd_models :: proc(a: ^App, args: string) {
	_ = args
	text := subagent.policy_list_text(context.temp_allocator)
	session.session_set_status(&a.session, text)
}

slash_cmd_agents :: proc(a: ^App, args: string) {
	rest := strings.trim_space(args)
	parts := strings.fields(rest, context.temp_allocator)
	if len(parts) == 0 || parts[0] == "list" {
		text := subagent.roster_status_text(&a.subagents.roster, context.temp_allocator)
		enabled := subagent.runtime_enabled(&a.subagents)
		session.session_set_status(&a.session, fmt.tprintf("subagents %s\n%s", enabled ? "on" : "off", text))
		return
	}
	switch parts[0] {
	case "off":
		subagent.runtime_set_session_off(&a.subagents, true)
		tools.register_subagent_tools(&a.tools_reg, false)
		session.session_set_status(&a.session, "subagents off")
	case "on":
		subagent.runtime_set_session_off(&a.subagents, false)
		tools.register_subagent_tools(&a.tools_reg, subagent.runtime_enabled(&a.subagents))
		session.session_set_status(&a.session, "subagents on")
	case "knowledge":
		text := subagent.knowledge_list(&a.subagents.knowledge, "", context.temp_allocator)
		session.session_set_status(&a.session, text)
	case "cancel":
		if len(parts) < 2 {
			session.session_set_status(&a.session, "usage: /agents cancel ID")
			return
		}
		subagent.roster_request_cancel(&a.subagents.roster, parts[1])
		session.session_set_status(&a.session, fmt.tprintf("cancel requested for %s", parts[1]))
	case "apply":
		force := false
		group := ""
		for i in 1 ..< len(parts) {
			if parts[i] == "--force" {
				force = true
			} else {
				group = parts[i]
			}
		}
		if len(group) == 0 {
			session.session_set_status(&a.session, "usage: /agents apply GROUP [--force]")
			return
		}
		ok, reason := subagent.roster_apply_allowed(&a.subagents.roster, group, force)
		if !ok {
			session.session_set_status(&a.session, reason)
			return
		}
		ws := ""
		if st := sandbox.state(); st != nil {
			ws = st.workspace
		}
		merged, merr := subagent.roster_apply_worktrees(&a.subagents.roster, group, ws, context.temp_allocator)
		if merr != "" {
			session.session_set_status(&a.session, merr)
			return
		}
		session.session_set_status(&a.session, fmt.tprintf("apply ok (merged %d) force=%v", merged, force))
	case:
		session.session_set_status(&a.session, "usage: /agents [list|on|off|knowledge|cancel ID|apply GROUP [--force]]")
	}
}

slash_cmd_approve :: proc(a: ^App, args: string) {
	_ = args
	path := a.session.last_plan_path
	if len(path) == 0 {
		session.session_set_status(&a.session, "no plan artifact to approve")
		return
	}
	if err := session.session_approve_plan_file(&a.session, path); len(err) > 0 {
		session.session_set_status(&a.session, err)
		return
	}
}

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
	session.session_set_status(
		&a.session,
		fmt.tprintf(
			"mode=%s plan_ok=%v verify=%s fails=%d input_chars=%d plan=%s",
			agent.mode_string(a.session.agent_mode),
			a.session.plan_contract_ok,
			verify,
			a.session.verify_fail_count,
			a.session.last_input_chars,
			plan,
		),
	)
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
	} else if p == .Ask {
		os.unset_env(constants.ENV_AUTONOMY)
		os.set_env(constants.ENV_SHELL_CONFIRM, "1")
	} else {
		os.unset_env(constants.ENV_AUTONOMY)
		os.unset_env(constants.ENV_SHELL_CONFIRM)
	}
	session.session_set_status(&a.session, fmt.tprintf("perms %s", tools.perms_string(p)))
}

slash_cmd_improve :: proc(a: ^App, args: string) {
	_ = args
	app_improve_prompt(a)
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

slash_cmd_reset :: proc(a: ^App, args: string) {
	rest := strings.to_lower(strings.trim_space(args), context.temp_allocator)
	if rest == "confirm" || rest == "yes" {
		if !a.reset_pending && rest == "yes" {
			session.session_set_status(&a.session, "type /reset then /reset confirm")
			return
		}
		ok := app_reset_all_state(a)
		if ok {
			app_toast_warn(a, "reset complete · setup next")
		} else {
			app_toast_error(a, "reset failed")
		}
		return
	}
	if rest == "cancel" || rest == "no" {
		a.reset_pending = false
		session.session_set_status(&a.session, "reset cancelled")
		app_toast(a, "reset cancelled", .Info)
		return
	}
	a.reset_pending = true
	session.session_set_status(
		&a.session,
		"DANGER: wipe sessions+env+keys · type /reset confirm",
	)
	app_toast_warn(a, "confirm with /reset confirm")
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

slash_cmd_undo :: proc(a: ^App, args: string) {
	_ = args
	msg, _ := tools.undo_last_write()
	session.session_set_status(&a.session, msg)
	delete(msg)
}

slash_cmd_copy :: proc(a: ^App, args: string) {
	_ = args
	if a.sel_has {
		_ = app_sel_copy(a)
		return
	}
	last := ""
	for i := len(a.session.messages) - 1; i >= 0; i -= 1 {
		if a.session.messages[i].role == .Assistant {
			last = a.session.messages[i].content
			break
		}
	}
	if len(last) == 0 {
		app_toast(a, "nothing to copy", .Warn)
		session.session_set_status(&a.session, "nothing to copy")
		return
	}
	if ui.clipboard_copy(last) {
		app_toast_ok(a, "copied to clipboard")
		session.session_set_status(&a.session, "last reply on clipboard")
	} else {
		app_toast_error(a, "clipboard copy failed")
		session.session_set_status(&a.session, "clipboard copy failed")
	}
}

slash_cmd_attach :: proc(a: ^App, args: string) {
	path := strings.trim_space(args)
	if len(path) == 0 {
		session.session_set_status(&a.session, "usage: /attach path")
		return
	}
	abs := tools.resolve_path(path, context.temp_allocator)
	if sandbox.path_is_secret_blocked(abs) {
		session.session_set_status(&a.session, "secret file blocked")
		return
	}
	data, err := os.read_entire_file(abs, context.temp_allocator)
	if err != nil {
		session.session_set_status(&a.session, "attach read failed")
		return
	}
	max_n := 32_000
	body := string(data)
	if len(body) > max_n {
		body = body[:max_n]
	}
	chunk := fmt.tprintf("\n\n[attached:%s]\n%s\n", path, body)
	app_insert_text(a, chunk)
	session.session_set_status(&a.session, fmt.tprintf("attached %s", path))
}

slash_cmd_view :: proc(a: ^App, args: string) {
	path := strings.trim_space(args)
	if len(path) == 0 {
		if a.view_open {
			app_view_close(a)
			session.session_set_status(&a.session, "view closed")
			return
		}
		session.session_set_status(&a.session, "usage: /view path")
		return
	}
	_ = app_view_open(a, path)
}

slash_cmd_close :: proc(a: ^App, args: string) {
	_ = args
	if !a.view_open {
		session.session_set_status(&a.session, "no file view open")
		return
	}
	app_view_close(a)
	session.session_set_status(&a.session, "view closed")
}
