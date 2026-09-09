// SPDX-License-Identifier: 0BSD
/*
Help, status, view pane, and slash suggestion input handlers.
*/

package app

import "core:fmt"
import "core:strings"
import "nullray:config"
import "nullray:session"
import "nullray:ui"

@(private)
app_handle_help_status_event :: proc(a: ^App, ev: ui.Event) -> (quit: bool, handled: bool) {
	if a.show_help {
		if ev.kind == .Esc || ev.kind == .F1 || config.binds_resolve(a.binds, ev.kind) == .Help {
			app_toggle_help(a)
			return false, true
		}
		if ev.kind == .Mouse_Press && ev.my == 0 && ev.mx >= a.help_btn_x {
			app_toggle_help(a)
			return false, true
		}
		if ev.kind == .Ctrl_Q || ev.kind == .Ctrl_C {
			return true, true
		}
		#partial switch ev.kind {
		case .Page_Up, .Up, .Mouse_Wheel_Up:
			step := 1
			if ev.kind == .Page_Up {
				step = max(8, a.loop.term.height / 2)
			}
			a.help_scroll = max(0, a.help_scroll - step)
			app_mark_dirty(a)
		case .Page_Down, .Down, .Mouse_Wheel_Down:
			step := 1
			if ev.kind == .Page_Down {
				step = max(8, a.loop.term.height / 2)
			}
			a.help_scroll += step
			app_mark_dirty(a)
		}
		return false, true
	}

	if a.show_status {
		if ev.kind == .Esc {
			a.show_status = false
			app_mark_dirty(a)
			return false, true
		}
		if ev.kind == .Ctrl_Q || ev.kind == .Ctrl_C {
			return true, true
		}
		#partial switch ev.kind {
		case .Page_Up, .Up, .Mouse_Wheel_Up:
			step := 1
			if ev.kind == .Page_Up {
				step = max(8, a.loop.term.height / 2)
			}
			a.status_scroll = max(0, a.status_scroll - step)
			app_mark_dirty(a)
		case .Page_Down, .Down, .Mouse_Wheel_Down:
			step := 1
			if ev.kind == .Page_Down {
				step = max(8, a.loop.term.height / 2)
			}
			a.status_scroll += step
			app_mark_dirty(a)
		}
		return false, true
	}

	return false, false
}

@(private)
app_handle_view_event :: proc(a: ^App, ev: ui.Event, suggesting: bool) -> bool {
	if !a.view_open || suggesting {
		return false
	}
	if ev.kind == .Tab {
		a.view_focus = !a.view_focus
		app_mark_dirty(a)
		return true
	}
	if ev.kind == .Esc && len(strings.to_string(a.input)) == 0 && !a.session.busy {
		app_view_close(a)
		session.session_set_status(&a.session, "view closed")
		return true
	}
	if a.view_focus {
		lay := app_view_layout(a, a.loop.term.width, a.loop.term.height)
		#partial switch ev.kind {
		case .Page_Up, .Up, .Mouse_Wheel_Up:
			step := 1
			if ev.kind == .Page_Up {
				step = max(8, lay.pane_h / 2)
			} else if ev.kind == .Mouse_Wheel_Up {
				step = 3
			}
			app_view_scroll_by(a, -step, lay.pane_h)
			return true
		case .Page_Down, .Down, .Mouse_Wheel_Down:
			step := 1
			if ev.kind == .Page_Down {
				step = max(8, lay.pane_h / 2)
			} else if ev.kind == .Mouse_Wheel_Down {
				step = 3
			}
			app_view_scroll_by(a, step, lay.pane_h)
			return true
		case .Left:
			app_view_switch(a, -1)
			return true
		case .Right:
			app_view_switch(a, 1)
			return true
		case .Rune:
			if ev.ch == '[' {
				app_view_switch(a, -1)
				return true
			}
			if ev.ch == ']' {
				app_view_switch(a, 1)
				return true
			}
		}
	} else if ev.kind == .Mouse_Wheel_Up || ev.kind == .Mouse_Wheel_Down {
		lay := app_view_layout(a, a.loop.term.width, a.loop.term.height)
		if lay.open && !lay.overlay && ev.mx >= lay.pane_x {
			step := 3
			if ev.kind == .Mouse_Wheel_Up {
				app_view_scroll_by(a, -step, lay.pane_h)
			} else {
				app_view_scroll_by(a, step, lay.pane_h)
			}
			return true
		}
	}
	return false
}

@(private)
app_handle_suggest_event :: proc(a: ^App, ev: ui.Event) -> bool {
	#partial switch ev.kind {
	case .Tab:
		_ = app_apply_suggestion(a)
		return true
	case .Up:
		a.suggest_sel = max(0, a.suggest_sel - 1)
		app_mark_dirty(a)
		return true
	case .Down:
		matches := slash_matches(strings.to_string(a.input))
		a.suggest_sel = min(len(matches) - 1, a.suggest_sel + 1)
		app_mark_dirty(a)
		return true
	case .Esc:
		if !a.session.busy {
			a.suggest_sel = 0
			app_mark_dirty(a)
			return true
		}
	case .Enter:
		if app_apply_suggestion(a) {
			text := strings.to_string(a.input)
			// If command needs args, leave it for editing
			needs_args := false
			for cmd in SLASH_COMMANDS {
				if text == fmt.tprintf("/%s", cmd.name) && strings.contains(cmd.usage, " ") {
					needs_args = true
					break
				}
			}
			if needs_args {
				strings.write_rune(&a.input, ' ')
				a.cursor = len(strings.to_string(a.input))
				app_mark_dirty(a)
				return true
			}
		}
	}
	return false
}
