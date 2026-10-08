// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Input orchestration, slash helpers, and submit.
*/

package app

import "core:strings"
import "nullray:hooks"
import "nullray:provider"
import "nullray:session"
import "nullray:tools"
import "nullray:ui"

app_toggle_help :: proc(a: ^App) {
	a.show_help = !a.show_help
	if a.show_help {
		a.help_scroll = 0
	}
	app_mark_dirty(a)
}

@(private)
slash_name_of :: proc(text: string) -> string {
	t := strings.trim_space(text)
	if !strings.has_prefix(t, "/") {
		return ""
	}
	body := t[1:]
	if sp := strings.index_byte(body, ' '); sp >= 0 {
		return body[:sp]
	}
	return body
}

@(private)
slash_busy_exempt :: proc(text: string) -> bool {
	name := slash_name_of(text)
	return name == "allow" || name == "deny" || name == "history"
}

@(private)
app_apply_suggestion :: proc(a: ^App) -> bool {
	text := strings.to_string(a.input)
	completed, ok := slash_complete(text, a.suggest_sel, a)
	if !ok {
		return false
	}
	strings.builder_reset(&a.input)
	strings.write_string(&a.input, completed)
	if !strings.has_suffix(completed, " ") {
		// leave bare command, user can add args or Enter to run
	}
	a.cursor = len(strings.to_string(a.input))
	a.suggest_sel = 0
	app_mark_dirty(a)
	return true
}

@(private)
app_handle_esc_idle :: proc(a: ^App) {
	if a.sel_has || a.sel_dragging {
		app_sel_clear(a)
		app_mark_dirty(a)
		return
	}
	if a.view_open && len(strings.to_string(a.input)) == 0 {
		app_view_close(a)
		session.session_set_status(a.session, "view closed")
		return
	}
	if len(strings.to_string(a.input)) > 0 {
		strings.builder_reset(&a.input)
		a.cursor = 0
		a.suggest_sel = 0
		app_mark_dirty(a)
	}
}

@(private)
app_mouse_in_transcript :: proc(a: ^App, mx, my: int) -> bool {
	h := a.loop.term.height
	w := a.loop.term.width
	c := app_chrome(a, w, h)
	if my < c.msg_top || my > c.msg_bottom {
		return false
	}
	lay := app_view_layout(a, w, h)
	if lay.open && !lay.overlay && mx >= lay.split_x {
		return false
	}
	return true
}

app_on_event :: proc(ev: ui.Event, user: rawptr) -> bool {
	a := cast(^App)user

	if splash_active(a) {
		// Any key or mouse ends splash early. Do not queue the event into the prompt.
		a.splash_on = false
		app_mark_dirty(a)
		return false
	}

	if a.show_setup {
		return app_setup_on_event(a, ev)
	}

	if a.elevate_active {
		return app_elevate_on_event(a, ev)
	}

	if a.ask_active {
		return app_ask_on_event(a, ev)
	}

	if quit, handled := app_handle_help_status_event(a, ev); handled {
		return quit
	}

	if a.tab_x_prefix {
		a.tab_x_prefix = false
		app_tab_prefix_key(a, ev)
		app_mark_dirty(a)
		return false
	}
	if ev.kind == .Ctrl_X {
		a.tab_x_prefix = true
		session.session_set_status(
			a.session,
			"tab: n new · w close · h/← prev · l/→ next · 1-9 jump · o sessions",
		)
		app_mark_dirty(a)
		return false
	}
	if ev.kind == .Mouse_Press && ev.my == 1 {
		// SGR button: 0 left, 1 middle, 2 right.
		right := ev.ch == 2
		if idx := app_tab_hit(a, ev.mx); idx >= 0 {
			if right {
				app_tab_close(a, idx)
			} else {
				app_tab_goto(a, idx)
			}
		} else if !right && a.tab_plus_x >= 0 && ev.mx >= a.tab_plus_x && ev.mx <= a.tab_plus_x + 2 {
			app_tab_new(a, "")
		}
		return false
	}

	if ev.kind == .Mouse_Press && app_help_btn_hit(a, ev.mx, ev.my) {
		app_toggle_help(a)
		return false
	}

	suggesting := len(slash_matches(strings.to_string(a.input), context.temp_allocator, a)) > 0

	if !suggesting && !(a.view_open && a.view_focus) {
		#partial switch ev.kind {
		case .Up:
			if app_history_up(a) {
				return false
			}
		case .Down:
			if app_history_down(a) {
				return false
			}
		}
	}

	if app_handle_view_event(a, ev, suggesting) {
		return false
	}

	if suggesting {
		if app_handle_suggest_event(a, ev) {
			return false
		}
	}

	if app_handle_line_edit(a, ev) {
		return false
	}

	if quit, handled := app_handle_bind_action(a, ev, suggesting); handled {
		return quit
	}

	if app_handle_default_event(a, ev) {
		return false
	}
	return false
}

app_submit :: proc(a: ^App) {
	text := strings.trim_space(strings.to_string(a.input))
	if len(text) == 0 && len(a.pending_media) == 0 {
		return
	}
	if a.session.busy && !slash_busy_exempt(text) {
		if strings.has_prefix(text, "/") {
			msg := "busy · Esc stop"
			if pending := tools.shell_pending(context.temp_allocator); len(pending) > 0 {
				msg = "busy · Esc stop · /allow|/deny"
			} else if a.elevate_active {
				msg = "busy · elevate active"
			}
			app_toast_warn(a, msg)
			return
		}
		if session.session_push_steer(a.session, text) {
			strings.builder_reset(&a.input)
			a.cursor = 0
			app_toast(a, "steered", .Info)
			app_mark_dirty(a)
			return
		}
		app_toast_warn(a, "busy · Esc stop")
		return
	}
	a.pasting = false
	strings.builder_reset(&a.input)
	a.cursor = 0
	a.scroll = 0
	a.follow = true
	a.input_hist_idx = -1
	delete(a.input_draft)
	a.input_draft = ""

	if app_handle_slash(a, text) {
		app_mark_dirty(a)
		return
	}

	// UserPromptSubmit hook: exit 2 blocks the prompt before it enters a turn.
	prompt_hook := hooks.run(.UserPromptSubmit, "", text, context.temp_allocator)
	if prompt_hook.blocked {
		msg := prompt_hook.message
		if len(msg) == 0 {
			msg = "prompt blocked by UserPromptSubmit hook"
		}
		session.session_set_status(a.session, msg)
		hooks.result_destroy(&prompt_hook, context.temp_allocator)
		app_mark_dirty(a)
		return
	}
	hooks.result_destroy(&prompt_hook, context.temp_allocator)

	app_history_push(a, text)
	app_reveal_reset(a)
	session.session_push_user_media(a.session, text, a.pending_media[:])
	app_media_clear(a)
	p := provider.registry_active(&a.registry)
	session.session_start_chat(a.session, p)
	app_mark_dirty(a)
}
