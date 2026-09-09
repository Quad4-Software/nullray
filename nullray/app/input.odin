// SPDX-License-Identifier: 0BSD
/*
Input orchestration, slash helpers, and submit.
*/

package app

import "core:strings"
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
	return name == "allow" || name == "deny"
}

@(private)
app_apply_suggestion :: proc(a: ^App) -> bool {
	text := strings.to_string(a.input)
	completed, ok := slash_complete(text, a.suggest_sel)
	if !ok {
		return false
	}
	strings.builder_reset(&a.input)
	strings.write_string(&a.input, completed)
	if !strings.has_suffix(completed, " ") {
		// leave bare command; user can add args or Enter to run
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
		session.session_set_status(&a.session, "view closed")
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
	input_rows := app_input_rows(a, w)
	if my < 2 || my > h - 2 - input_rows {
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

	if quit, handled := app_handle_help_status_event(a, ev); handled {
		return quit
	}

	if ev.kind == .Mouse_Press && ev.my == 0 && ev.mx >= a.help_btn_x {
		app_toggle_help(a)
		return false
	}

	suggesting := len(slash_matches(strings.to_string(a.input))) > 0

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
	if len(text) == 0 {
		return
	}
	if a.session.busy && !slash_busy_exempt(text) {
		msg := "busy · Esc stop"
		if pending := tools.shell_pending(context.temp_allocator); len(pending) > 0 {
			msg = "busy · Esc stop · /allow|/deny"
		} else if a.elevate_active {
			msg = "busy · elevate active"
		}
		app_toast_warn(a, msg)
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

	app_history_push(a, text)
	app_reveal_reset(a)
	session.session_push_user(&a.session, text)
	p := provider.registry_active(&a.registry)
	session.session_start_chat(&a.session, p)
	app_mark_dirty(a)
}
