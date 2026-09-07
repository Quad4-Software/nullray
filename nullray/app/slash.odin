/*
Slash command dispatch for the TUI.
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
import "nullray:tools"
import "nullray:ui"

app_handle_slash :: proc(a: ^App, text: string) -> bool {
	if text == "/help" || text == "/?" {
		app_toggle_help(a)
		return true
	}
	if text == "/keys" {
		help := config.binds_help_text(a.binds, a.keys_preset)
		session.session_push_assistant(&a.session, help)
		delete(help)
		session.session_set_status(&a.session, "keys")
		return true
	}
	if text == "/themes" {
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
		return true
	}
	if strings.has_prefix(text, "/theme ") {
		name := strings.trim_space(text[len("/theme "):])
		if !ui.theme_exists(name) {
			session.session_set_status(&a.session, "usage: /theme ink|ember|moss|slate|rose|mono|dusk")
			return true
		}
		ui.theme_set(ui.theme_by_name(name))
		if a.loop != nil {
			a.loop.theme = ui.theme()
			ui.loop_request_full_redraw(a.loop)
		}
		session.session_set_status(&a.session, fmt.tprintf("theme %s", ui.theme().name))
		app_mark_dirty(a)
		return true
	}
	if text == "/theme" {
		session.session_set_status(&a.session, fmt.tprintf("theme %s", ui.theme().name))
		return true
	}
	if text == "/compact" {
		p := provider.registry_active(&a.registry)
		_ = session.session_compact_with_provider(&a.session, p)
		return true
	}
	if text == "/tools" {
		a.session.tools_enabled = !a.session.tools_enabled
		mode := "tools on"
		if !a.session.tools_enabled {
			mode = "tools off"
		}
		session.session_set_status(&a.session, mode)
		return true
	}
	if text == "/reasoning" || text == "/think" {
		session.session_set_status(&a.session, fmt.tprintf("reasoning %s (none|minimal|low|medium|high|xhigh|max)", a.session.reasoning_effort))
		return true
	}
	if strings.has_prefix(text, "/reasoning ") || strings.has_prefix(text, "/think ") {
		rest := text
		if strings.has_prefix(text, "/reasoning ") {
			rest = text[len("/reasoning "):]
		} else {
			rest = text[len("/think "):]
		}
		effort, ok := session.normalize_reasoning_effort(rest)
		if !ok {
			session.session_set_status(&a.session, "usage: /reasoning none|minimal|low|medium|high|xhigh|max")
			return true
		}
		delete(a.session.reasoning_effort)
		a.session.reasoning_effort = strings.clone(effort)
		session.session_set_status(&a.session, fmt.tprintf("reasoning %s", a.session.reasoning_effort))
		return true
	}
	if text == "/sessions" || text == "/session" {
		list := session.session_list_text()
		session.session_push_assistant(&a.session, list)
		delete(list)
		session.session_set_status(&a.session, "sessions")
		return true
	}
	if strings.has_prefix(text, "/search ") {
		q := strings.trim_space(text[len("/search "):])
		list := session.session_search_text(q)
		session.session_push_assistant(&a.session, list)
		delete(list)
		session.session_set_status(&a.session, "search")
		return true
	}
	if text == "/search" {
		session.session_set_status(&a.session, "usage: /search query")
		return true
	}
	if strings.has_prefix(text, "/resume ") || strings.has_prefix(text, "/switch ") {
		name := ""
		if strings.has_prefix(text, "/resume ") {
			name = strings.trim_space(text[len("/resume "):])
		} else {
			name = strings.trim_space(text[len("/switch "):])
		}
		if len(name) == 0 {
			session.session_set_status(&a.session, "usage: /resume name")
			return true
		}
		if session.session_switch(&a.session, name) {
			_ = session.session_apply_saved_model(&a.session, &a.registry)
			app_refresh_credits(a)
			session.session_set_status(&a.session, fmt.tprintf("resumed %s", a.session.name))
		} else {
			session.session_set_status(&a.session, fmt.tprintf("no session %s", name))
		}
		return true
	}
	if strings.has_prefix(text, "/name ") {
		name := strings.trim_space(text[len("/name "):])
		if len(name) == 0 {
			session.session_set_status(&a.session, "usage: /name name")
			return true
		}
		_ = session.session_rename(&a.session, name)
		return true
	}
	if strings.has_prefix(text, "/new") {
		rest := strings.trim_space(text[len("/new"):])
		name := rest
		if len(name) == 0 {
			name = "session"
		}
		_ = session.session_new(&a.session, name)
		return true
	}
	if strings.has_prefix(text, "/fork ") {
		name := strings.trim_space(text[len("/fork "):])
		if len(name) == 0 {
			session.session_set_status(&a.session, "usage: /fork name")
			return true
		}
		_ = session.session_fork(&a.session, name)
		return true
	}
	if text == "/ephemeral" || text == "/ephemeral on" {
		session.session_set_ephemeral(&a.session, true)
		return true
	}
	if text == "/ephemeral off" {
		session.session_set_ephemeral(&a.session, false)
		return true
	}
	if text == "/group" {
		g := a.session.group
		if len(g) == 0 {
			g = "(none)"
		}
		session.session_set_status(&a.session, fmt.tprintf("group %s", g))
		return true
	}
	if strings.has_prefix(text, "/group ") {
		name := strings.trim_space(text[len("/group "):])
		session.session_set_group(&a.session, name)
		return true
	}
	if text == "/mode" {
		session.session_set_status(&a.session, fmt.tprintf("mode %s (ask|plan|edit)", agent.mode_string(a.session.agent_mode)))
		return true
	}
	if strings.has_prefix(text, "/mode ") {
		rest := strings.trim_space(text[len("/mode "):])
		m, ok := agent.mode_from_string(rest)
		if !ok {
			session.session_set_status(&a.session, "usage: /mode ask|plan|edit")
			return true
		}
		session.session_set_mode(&a.session, m)
		return true
	}
	if text == "/perms" {
		session.session_set_status(
			&a.session,
			fmt.tprintf("perms %s (ask|allow|yolo)", tools.perms_string(tools.perms_from_env())),
		)
		return true
	}
	if strings.has_prefix(text, "/perms ") {
		rest := strings.trim_space(text[len("/perms "):])
		p, ok := tools.perms_from_string(rest)
		if !ok {
			session.session_set_status(&a.session, "usage: /perms ask|allow|yolo")
			return true
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
		return true
	}
	if text == "/improve" {
		app_improve_prompt(a)
		return true
	}
	if text == "/pause" {
		if a.session.busy {
			session.session_request_pause(&a.session)
		} else {
			session.session_set_status(&a.session, "not running")
		}
		return true
	}
	if text == "/stop" || text == "/cancel" {
		if a.session.busy {
			session.session_request_cancel(&a.session)
		} else {
			session.session_set_status(&a.session, "not running")
		}
		return true
	}
	if text == "/continue" || strings.has_prefix(text, "/continue ") {
		extra := ""
		if strings.has_prefix(text, "/continue ") {
			extra = strings.trim_space(text[len("/continue "):])
		}
		p := provider.registry_active(&a.registry)
		session.session_resume(&a.session, p, extra)
		app_mark_dirty(a)
		return true
	}
	if text == "/auto" {
		on := agent.auto_from_env()
		session.session_set_status(&a.session, fmt.tprintf("auto %s (use /auto on|off)", on ? "on" : "off"))
		return true
	}
	if text == "/auto on" {
		os.set_env(constants.ENV_AUTO, "1")
		agent.apply_auto_mode()
		session.session_set_mode(&a.session, .Edit)
		session.session_set_status(&a.session, "auto on (edit + yolo)")
		return true
	}
	if text == "/auto off" {
		os.unset_env(constants.ENV_AUTO)
		os.unset_env(constants.ENV_AUTONOMY)
		os.set_env(constants.ENV_PERMS, "allow")
		session.session_set_status(&a.session, "auto off")
		return true
	}
	if strings.has_prefix(text, "/secrets ") {
		path := strings.trim_space(text[len("/secrets "):])
		if len(path) == 0 {
			session.session_set_status(&a.session, "usage: /secrets path")
			return true
		}
		cur, _ := os.lookup_env(constants.ENV_SECRETS_ALLOW, context.temp_allocator)
		if len(cur) > 0 {
			os.set_env(constants.ENV_SECRETS_ALLOW, fmt.tprintf("%s,%s", cur, path))
		} else {
			os.set_env(constants.ENV_SECRETS_ALLOW, path)
		}
		session.session_set_status(&a.session, fmt.tprintf("secrets allow += %s", path))
		return true
	}
	if text == "/secrets" {
		cur, ok := os.lookup_env(constants.ENV_SECRETS_ALLOW, context.temp_allocator)
		if !ok || len(cur) == 0 {
			cur = "(none)"
		}
		session.session_set_status(&a.session, fmt.tprintf("NULLRAY_SECRETS_ALLOW=%s", cur))
		return true
	}
	if text == "/review" {
		on := agent.review_enabled_from_env()
		session.session_set_status(&a.session, fmt.tprintf("review %s (NULLRAY_REVIEW_MODEL optional)", on ? "on" : "off"))
		return true
	}
	if text == "/review on" {
		os.set_env(constants.ENV_REVIEW, "on")
		session.session_set_status(&a.session, "review on")
		return true
	}
	if text == "/review off" {
		os.set_env(constants.ENV_REVIEW, "off")
		session.session_set_status(&a.session, "review off")
		return true
	}
	if text == "/allow" {
		cmd, ok := tools.shell_allow_once()
		if !ok {
			session.session_set_status(&a.session, "no pending shell command")
			return true
		}
		session.session_set_status(&a.session, fmt.tprintf("allowed once: %s (agent may retry)", cmd))
		delete(cmd)
		return true
	}
	if text == "/deny" {
		tools.shell_deny_pending()
		session.session_set_status(&a.session, "pending shell denied")
		return true
	}
	if text == "/undo" {
		msg, _ := tools.undo_last_write()
		session.session_set_status(&a.session, msg)
		delete(msg)
		return true
	}
	if text == "/copy" {
		last := ""
		for i := len(a.session.messages) - 1; i >= 0; i -= 1 {
			if a.session.messages[i].role == .Assistant {
				last = a.session.messages[i].content
				break
			}
		}
		if len(last) == 0 {
			session.session_set_status(&a.session, "nothing to copy")
			return true
		}
		if ui.clipboard_copy(last) {
			session.session_set_status(&a.session, "last reply on clipboard")
		} else {
			session.session_set_status(&a.session, "clipboard copy failed")
		}
		return true
	}
	if strings.has_prefix(text, "/attach ") {
		path := strings.trim_space(text[len("/attach "):])
		if len(path) == 0 {
			session.session_set_status(&a.session, "usage: /attach path")
			return true
		}
		abs := tools.resolve_path(path, context.temp_allocator)
		if sandbox.path_is_secret_blocked(abs) {
			session.session_set_status(&a.session, "secret file blocked")
			return true
		}
		data, err := os.read_entire_file(abs, context.temp_allocator)
		if err != nil {
			session.session_set_status(&a.session, "attach read failed")
			return true
		}
		max_n := 32_000
		body := string(data)
		if len(body) > max_n {
			body = body[:max_n]
		}
		chunk := fmt.tprintf("\n\n[attached:%s]\n%s\n", path, body)
		app_insert_text(a, chunk)
		session.session_set_status(&a.session, fmt.tprintf("attached %s", path))
		return true
	}
	return false
}

