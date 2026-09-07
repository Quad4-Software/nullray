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
import "nullray:store"
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
	last := ""
	for i := len(a.session.messages) - 1; i >= 0; i -= 1 {
		if a.session.messages[i].role == .Assistant {
			last = a.session.messages[i].content
			break
		}
	}
	if len(last) == 0 {
		session.session_set_status(&a.session, "nothing to copy")
		return
	}
	if ui.clipboard_copy(last) {
		session.session_set_status(&a.session, "last reply on clipboard")
	} else {
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
