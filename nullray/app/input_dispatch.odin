// SPDX-License-Identifier: 0BSD
/*
Key bind actions and default input event dispatch.
*/

package app

import "core:strings"
import "nullray:config"
import "nullray:provider"
import "nullray:session"
import "nullray:ui"

@(private)
app_handle_bind_action :: proc(a: ^App, ev: ui.Event, suggesting: bool) -> (quit: bool, handled: bool) {
	action := config.binds_resolve(a.binds, ev.kind)
	switch action {
	case .Quit:
		// Ctrl-C while busy stops the agent. Ctrl-Q (or Ctrl-C when idle) quits.
		if a.session.busy && ev.kind == .Ctrl_C {
			session.session_request_cancel(&a.session)
			a.pasting = false
			app_mark_dirty(a)
			return false, true
		}
		if a.session.busy {
			session.session_request_cancel(&a.session)
		}
		return true, true
	case .Help:
		app_toggle_help(a)
		return false, true
	case .Clear_Chat:
		if a.session.busy {
			session.session_set_status(&a.session, "stopping · clear chat after stop")
			app_mark_dirty(a)
			return false, true
		}
		for m in a.session.messages {
			provider.destroy_message(m)
		}
		clear(&a.session.messages)
		session.session_clear_streaming(&a.session)
		session.session_set_status(&a.session, "cleared")
		session.session_maybe_persist(&a.session)
		app_mark_dirty(a)
		return false, true
	case .Provider_Next:
		provider.registry_cycle(&a.registry, 1)
		app_activate_provider(a)
		return false, true
	case .Provider_Prev:
		provider.registry_cycle(&a.registry, -1)
		app_activate_provider(a)
		return false, true
	case .Compact:
		p := provider.registry_active(&a.registry)
		if session.session_compact_with_provider(&a.session, p) {
			app_mark_dirty(a)
		}
		return false, true
	case .Toggle_Tools:
		a.session.tools_enabled = !a.session.tools_enabled
		mode := "tools on"
		if !a.session.tools_enabled {
			mode = "tools off"
		}
		session.session_set_status(&a.session, mode)
		app_mark_dirty(a)
		return false, true
	case .Clear_Input:
		strings.builder_reset(&a.input)
		a.cursor = 0
		a.suggest_sel = 0
		app_mark_dirty(a)
		return false, true
	case .Scroll_Up:
		if !suggesting {
			if a.view_open && a.view_focus {
				lay := app_view_layout(a, a.loop.term.width, a.loop.term.height)
				app_view_scroll_by(a, -1, lay.pane_h)
			} else if app_history_up(a) {
				return false, true
			} else {
				app_scroll_by(a, 1)
			}
		}
		return false, true
	case .Scroll_Down:
		if !suggesting {
			if a.view_open && a.view_focus {
				lay := app_view_layout(a, a.loop.term.width, a.loop.term.height)
				app_view_scroll_by(a, 1, lay.pane_h)
			} else if app_history_down(a) {
				return false, true
			} else {
				app_scroll_by(a, -1)
			}
		}
		return false, true
	case .Page_Up:
		if a.view_open && a.view_focus {
			lay := app_view_layout(a, a.loop.term.width, a.loop.term.height)
			app_view_scroll_by(a, -max(8, lay.pane_h / 2), lay.pane_h)
		} else {
			app_scroll_by(a, max(8, a.loop.term.height / 2))
		}
		return false, true
	case .Page_Down:
		if a.view_open && a.view_focus {
			lay := app_view_layout(a, a.loop.term.width, a.loop.term.height)
			app_view_scroll_by(a, max(8, lay.pane_h / 2), lay.pane_h)
		} else {
			app_scroll_by(a, -max(8, a.loop.term.height / 2))
		}
		return false, true
	case .Follow_Bottom:
		app_follow_bottom(a)
		return false, true
	case .Scroll_Top:
		app_scroll_to_top(a)
		return false, true
	case .Improve_Prompt:
		app_improve_prompt(a)
		return false, true
	case .Undo_Improve:
		app_undo_improve(a)
		return false, true
	case .Pause_Agent:
		if a.session.busy {
			session.session_request_pause(&a.session)
			app_mark_dirty(a)
		}
		return false, true
	case .Stop_Agent:
		if a.session.busy {
			session.session_request_cancel(&a.session)
			a.pasting = false
			app_mark_dirty(a)
			return false, true
		}
		app_handle_esc_idle(a)
		return false, true
	case .None:
	}
	return false, false
}

@(private)
app_handle_default_event :: proc(a: ^App, ev: ui.Event) -> bool {
	#partial switch ev.kind {
	case .Paste_Start:
		a.pasting = true
		return true
	case .Paste_End:
		a.pasting = false
		app_mark_dirty(a)
		return true
	case .Ctrl_J:
		app_insert_text(a, "\n")
		return true
	case .Ctrl_V, .Ctrl_Y:
		if text, ok := ui.clipboard_paste(); ok {
			app_insert_text(a, text)
			delete(text)
		}
		return true
	case .Enter:
		if a.pasting {
			app_insert_text(a, "\n")
		} else {
			app_submit(a)
		}
		return true
	case .Backspace:
		text := strings.to_string(a.input)
		a.cursor = ui.cursor_snap_boundary(text, a.cursor)
		if a.cursor > 0 && len(text) > 0 {
			cut := ui.cursor_prev_edit(text, a.cursor)
			left := text[:cut]
			right := text[a.cursor:]
			strings.builder_reset(&a.input)
			strings.write_string(&a.input, left)
			strings.write_string(&a.input, right)
			a.cursor = cut
			a.suggest_sel = 0
			app_mark_dirty(a)
		}
		return true
	case .Delete:
		app_delete_forward(a)
		return true
	case .Left:
		text := strings.to_string(a.input)
		a.cursor = ui.cursor_prev_rune(text, a.cursor)
		app_mark_dirty(a)
		return true
	case .Right:
		text := strings.to_string(a.input)
		a.cursor = ui.cursor_next_rune(text, a.cursor)
		app_mark_dirty(a)
		return true
	case .Home:
		if a.keys_preset != .Default {
			a.cursor = 0
			app_mark_dirty(a)
		}
		return true
	case .End:
		if a.keys_preset != .Default {
			a.cursor = len(strings.to_string(a.input))
			app_mark_dirty(a)
		}
		return true
	case .Mouse_Wheel_Up:
		app_scroll_by(a, 3)
		return true
	case .Mouse_Wheel_Down:
		app_scroll_by(a, -3)
		return true
	case .Mouse_Press:
		input_rows := app_input_rows(a, a.loop.term.width)
		if ev.my >= a.loop.term.height - input_rows {
			app_follow_bottom(a)
			return true
		}
		if app_try_click_expand(a, ev.mx, ev.my) {
			return true
		}
		if ev.ch == 0 && app_mouse_in_transcript(a, ev.mx, ev.my) {
			app_sel_start(a, ev.mx, ev.my)
			return true
		}
	case .Mouse_Drag:
		if a.sel_dragging && ev.ch == 0 {
			app_sel_update(a, ev.mx, ev.my)
			return true
		}
	case .Mouse_Release:
		if a.sel_dragging && ev.ch == 0 {
			moved := ev.mx != a.sel_ax || ev.my != a.sel_ay
			if !moved {
				a.sel_dragging = false
				_ = app_sel_click_message(a, ev.my)
			} else {
				app_sel_finish(a, ev.mx, ev.my, false)
			}
			return true
		}
	case .Rune:
		// Allow typing while busy so /allow and /deny can be entered mid-turn.
		if ev.ch >= 0x20 {
			if a.sel_has {
				app_sel_clear(a)
			}
			app_insert_rune(a, ev.ch)
		}
		return true
	case .Esc:
		app_handle_esc_idle(a)
		return true
	}
	return false
}
