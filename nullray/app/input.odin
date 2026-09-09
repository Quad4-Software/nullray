// SPDX-License-Identifier: 0BSD
/*
Input events, editing, scroll, prompt improve, submit.
*/

package app

import "core:fmt"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:unicode/utf8"
import "nullray:agent"
import "nullray:config"
import "nullray:constants"
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

	if a.show_help {
		if ev.kind == .Esc || ev.kind == .F1 || config.binds_resolve(a.binds, ev.kind) == .Help {
			app_toggle_help(a)
			return false
		}
		if ev.kind == .Mouse_Press && ev.my == 0 && ev.mx >= a.help_btn_x {
			app_toggle_help(a)
			return false
		}
		if ev.kind == .Ctrl_Q || ev.kind == .Ctrl_C {
			return true
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
		return false
	}

	if a.show_status {
		if ev.kind == .Esc {
			a.show_status = false
			app_mark_dirty(a)
			return false
		}
		if ev.kind == .Ctrl_Q || ev.kind == .Ctrl_C {
			return true
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
		return false
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

	if a.view_open && !suggesting {
		if ev.kind == .Tab {
			a.view_focus = !a.view_focus
			app_mark_dirty(a)
			return false
		}
		if ev.kind == .Esc && len(strings.to_string(a.input)) == 0 && !a.session.busy {
			app_view_close(a)
			session.session_set_status(&a.session, "view closed")
			return false
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
				return false
			case .Page_Down, .Down, .Mouse_Wheel_Down:
				step := 1
				if ev.kind == .Page_Down {
					step = max(8, lay.pane_h / 2)
				} else if ev.kind == .Mouse_Wheel_Down {
					step = 3
				}
				app_view_scroll_by(a, step, lay.pane_h)
				return false
			case .Left:
				app_view_switch(a, -1)
				return false
			case .Right:
				app_view_switch(a, 1)
				return false
			case .Rune:
				if ev.ch == '[' {
					app_view_switch(a, -1)
					return false
				}
				if ev.ch == ']' {
					app_view_switch(a, 1)
					return false
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
				return false
			}
		}
	}

	if suggesting {
		#partial switch ev.kind {
		case .Tab:
			_ = app_apply_suggestion(a)
			return false
		case .Up:
			a.suggest_sel = max(0, a.suggest_sel - 1)
			app_mark_dirty(a)
			return false
		case .Down:
			matches := slash_matches(strings.to_string(a.input))
			a.suggest_sel = min(len(matches) - 1, a.suggest_sel + 1)
			app_mark_dirty(a)
			return false
		case .Esc:
			if !a.session.busy {
				a.suggest_sel = 0
				app_mark_dirty(a)
				return false
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
					return false
				}
			}
		}
	}

	if app_handle_line_edit(a, ev) {
		return false
	}

	action := config.binds_resolve(a.binds, ev.kind)
	switch action {
	case .Quit:
		// Ctrl-C while busy stops the agent. Ctrl-Q (or Ctrl-C when idle) quits.
		if a.session.busy && ev.kind == .Ctrl_C {
			session.session_request_cancel(&a.session)
			a.pasting = false
			app_mark_dirty(a)
			return false
		}
		if a.session.busy {
			session.session_request_cancel(&a.session)
		}
		return true
	case .Help:
		app_toggle_help(a)
		return false
	case .Clear_Chat:
		if a.session.busy {
			session.session_set_status(&a.session, "stopping · clear chat after stop")
			app_mark_dirty(a)
			return false
		}
		for m in a.session.messages {
			provider.destroy_message(m)
		}
		clear(&a.session.messages)
		session.session_clear_streaming(&a.session)
		session.session_set_status(&a.session, "cleared")
		session.session_maybe_persist(&a.session)
		app_mark_dirty(a)
		return false
	case .Provider_Next:
		provider.registry_cycle(&a.registry, 1)
		app_activate_provider(a)
		return false
	case .Provider_Prev:
		provider.registry_cycle(&a.registry, -1)
		app_activate_provider(a)
		return false
	case .Compact:
		p := provider.registry_active(&a.registry)
		if session.session_compact_with_provider(&a.session, p) {
			app_mark_dirty(a)
		}
		return false
	case .Toggle_Tools:
		a.session.tools_enabled = !a.session.tools_enabled
		mode := "tools on"
		if !a.session.tools_enabled {
			mode = "tools off"
		}
		session.session_set_status(&a.session, mode)
		app_mark_dirty(a)
		return false
	case .Clear_Input:
		strings.builder_reset(&a.input)
		a.cursor = 0
		a.suggest_sel = 0
		app_mark_dirty(a)
		return false
	case .Scroll_Up:
		if !suggesting {
			if a.view_open && a.view_focus {
				lay := app_view_layout(a, a.loop.term.width, a.loop.term.height)
				app_view_scroll_by(a, -1, lay.pane_h)
			} else if app_history_up(a) {
				return false
			} else {
				app_scroll_by(a, 1)
			}
		}
		return false
	case .Scroll_Down:
		if !suggesting {
			if a.view_open && a.view_focus {
				lay := app_view_layout(a, a.loop.term.width, a.loop.term.height)
				app_view_scroll_by(a, 1, lay.pane_h)
			} else if app_history_down(a) {
				return false
			} else {
				app_scroll_by(a, -1)
			}
		}
		return false
	case .Page_Up:
		if a.view_open && a.view_focus {
			lay := app_view_layout(a, a.loop.term.width, a.loop.term.height)
			app_view_scroll_by(a, -max(8, lay.pane_h / 2), lay.pane_h)
		} else {
			app_scroll_by(a, max(8, a.loop.term.height / 2))
		}
		return false
	case .Page_Down:
		if a.view_open && a.view_focus {
			lay := app_view_layout(a, a.loop.term.width, a.loop.term.height)
			app_view_scroll_by(a, max(8, lay.pane_h / 2), lay.pane_h)
		} else {
			app_scroll_by(a, -max(8, a.loop.term.height / 2))
		}
		return false
	case .Follow_Bottom:
		app_follow_bottom(a)
		return false
	case .Scroll_Top:
		app_scroll_to_top(a)
		return false
	case .Improve_Prompt:
		app_improve_prompt(a)
		return false
	case .Undo_Improve:
		app_undo_improve(a)
		return false
	case .Pause_Agent:
		if a.session.busy {
			session.session_request_pause(&a.session)
			app_mark_dirty(a)
		}
		return false
	case .Stop_Agent:
		if a.session.busy {
			session.session_request_cancel(&a.session)
			a.pasting = false
			app_mark_dirty(a)
			return false
		}
		app_handle_esc_idle(a)
		return false
	case .None:
	}

	#partial switch ev.kind {
	case .Paste_Start:
		a.pasting = true
		return false
	case .Paste_End:
		a.pasting = false
		app_mark_dirty(a)
		return false
	case .Ctrl_J:
		app_insert_text(a, "\n")
		return false
	case .Ctrl_V, .Ctrl_Y:
		if text, ok := ui.clipboard_paste(); ok {
			app_insert_text(a, text)
			delete(text)
		}
		return false
	case .Enter:
		if a.pasting {
			app_insert_text(a, "\n")
		} else {
			app_submit(a)
		}
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
	case .Delete:
		app_delete_forward(a)
	case .Left:
		text := strings.to_string(a.input)
		a.cursor = ui.cursor_prev_rune(text, a.cursor)
		app_mark_dirty(a)
	case .Right:
		text := strings.to_string(a.input)
		a.cursor = ui.cursor_next_rune(text, a.cursor)
		app_mark_dirty(a)
	case .Home:
		if a.keys_preset != .Default {
			a.cursor = 0
			app_mark_dirty(a)
		}
	case .End:
		if a.keys_preset != .Default {
			a.cursor = len(strings.to_string(a.input))
			app_mark_dirty(a)
		}
	case .Mouse_Wheel_Up:
		app_scroll_by(a, 3)
	case .Mouse_Wheel_Down:
		app_scroll_by(a, -3)
	case .Mouse_Press:
		input_rows := app_input_rows(a, a.loop.term.width)
		if ev.my >= a.loop.term.height - input_rows {
			app_follow_bottom(a)
			return false
		}
		if app_try_click_expand(a, ev.mx, ev.my) {
			return false
		}
		if ev.ch == 0 && app_mouse_in_transcript(a, ev.mx, ev.my) {
			app_sel_start(a, ev.mx, ev.my)
			return false
		}
	case .Mouse_Drag:
		if a.sel_dragging && ev.ch == 0 {
			app_sel_update(a, ev.mx, ev.my)
			return false
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
			return false
		}
	case .Rune:
		// Allow typing while busy so /allow and /deny can be entered mid-turn.
		if ev.ch >= 0x20 {
			if a.sel_has {
				app_sel_clear(a)
			}
			app_insert_rune(a, ev.ch)
		}
	case .Esc:
		app_handle_esc_idle(a)
	}
	return false
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

@(private)
app_handle_line_edit :: proc(a: ^App, ev: ui.Event) -> bool {
	switch a.keys_preset {
	case .Default:
		return false
	case .Neovim:
		#partial switch ev.kind {
		case .Ctrl_W:
			app_kill_word_back(a)
			return true
		case .Ctrl_U:
			app_kill_to_start(a)
			return true
		}
	case .Emacs:
		#partial switch ev.kind {
		case .Ctrl_A:
			a.cursor = 0
			app_mark_dirty(a)
			return true
		case .Ctrl_E:
			a.cursor = len(strings.to_string(a.input))
			app_mark_dirty(a)
			return true
		case .Ctrl_B:
			text := strings.to_string(a.input)
			a.cursor = ui.cursor_prev_rune(text, a.cursor)
			app_mark_dirty(a)
			return true
		case .Ctrl_F:
			text := strings.to_string(a.input)
			a.cursor = ui.cursor_next_rune(text, a.cursor)
			app_mark_dirty(a)
			return true
		case .Ctrl_K:
			app_kill_to_end(a)
			return true
		case .Ctrl_W:
			app_kill_word_back(a)
			return true
		case .Ctrl_D:
			app_delete_forward(a)
			return true
		case .Ctrl_U:
			app_kill_to_start(a)
			return true
		}
	}
	return false
}

@(private)
app_kill_word_back :: proc(a: ^App) {
	text := strings.to_string(a.input)
	a.cursor = ui.cursor_snap_boundary(text, a.cursor)
	if a.cursor <= 0 || len(text) == 0 {
		return
	}
	i := a.cursor
	for i > 0 {
		prev := ui.cursor_prev_rune(text, i)
		r, _ := utf8.decode_rune_in_string(text[prev:i])
		if r != ' ' {
			break
		}
		i = prev
	}
	for i > 0 {
		prev := ui.cursor_prev_rune(text, i)
		r, _ := utf8.decode_rune_in_string(text[prev:i])
		if r == ' ' {
			break
		}
		i = prev
	}
	left := text[:i]
	right := text[a.cursor:]
	strings.builder_reset(&a.input)
	strings.write_string(&a.input, left)
	strings.write_string(&a.input, right)
	a.cursor = i
	a.suggest_sel = 0
	app_mark_dirty(a)
}

@(private)
app_kill_to_start :: proc(a: ^App) {
	text := strings.to_string(a.input)
	a.cursor = ui.cursor_snap_boundary(text, a.cursor)
	if a.cursor <= 0 {
		return
	}
	right := text[a.cursor:]
	strings.builder_reset(&a.input)
	strings.write_string(&a.input, right)
	a.cursor = 0
	a.suggest_sel = 0
	app_mark_dirty(a)
}

@(private)
app_kill_to_end :: proc(a: ^App) {
	text := strings.to_string(a.input)
	a.cursor = ui.cursor_snap_boundary(text, a.cursor)
	if a.cursor >= len(text) {
		return
	}
	left := text[:a.cursor]
	strings.builder_reset(&a.input)
	strings.write_string(&a.input, left)
	a.suggest_sel = 0
	app_mark_dirty(a)
}

@(private)
app_delete_forward :: proc(a: ^App) {
	text := strings.to_string(a.input)
	a.cursor = ui.cursor_snap_boundary(text, a.cursor)
	if a.cursor >= len(text) {
		return
	}
	end := ui.cursor_next_rune(text, a.cursor)
	left := text[:a.cursor]
	right := text[end:]
	strings.builder_reset(&a.input)
	strings.write_string(&a.input, left)
	strings.write_string(&a.input, right)
	a.suggest_sel = 0
	app_mark_dirty(a)
}

@(private)
app_insert_text :: proc(a: ^App, s: string) {
	text := strings.to_string(a.input)
	a.cursor = ui.cursor_snap_boundary(text, a.cursor)
	room := constants.MAX_INPUT_CHARS - len(text)
	if room <= 0 {
		app_toast_warn(a, "input full")
		return
	}
	chunk := s
	if len(chunk) > room {
		chunk = ui.truncate_utf8_bytes(s, room)
		app_toast_warn(a, fmt.tprintf("paste truncated to %d chars", len(chunk)))
	}
	if len(chunk) == 0 {
		return
	}
	left := text[:a.cursor]
	right := text[a.cursor:]
	strings.builder_reset(&a.input)
	strings.write_string(&a.input, left)
	strings.write_string(&a.input, chunk)
	strings.write_string(&a.input, right)
	a.cursor += len(chunk)
	a.suggest_sel = 0
	app_mark_dirty(a)
}

@(private)
app_insert_rune :: proc(a: ^App, ch: rune) {
	text := strings.to_string(a.input)
	a.cursor = ui.cursor_snap_boundary(text, a.cursor)
	buf, n := utf8.encode_rune(ch)
	if n <= 0 {
		return
	}
	if len(text) + n > constants.MAX_INPUT_CHARS {
		app_toast_warn(a, "input full")
		return
	}
	left := text[:a.cursor]
	right := text[a.cursor:]
	strings.builder_reset(&a.input)
	strings.write_string(&a.input, left)
	strings.write_string(&a.input, string(buf[:n]))
	strings.write_string(&a.input, right)
	a.cursor = len(strings.to_string(a.input)) - len(right)
	a.suggest_sel = 0
	app_mark_dirty(a)
}

@(private)
app_scroll_by :: proc(a: ^App, delta: int) {
	if delta == 0 {
		return
	}
	a.follow = false
	a.scroll = max(0, a.scroll + delta)
	if a.scroll == 0 {
		a.follow = true
	}
	app_mark_dirty(a)
}

@(private)
app_scroll_to_top :: proc(a: ^App) {
	a.follow = false
	a.scroll = 1_000_000
	app_mark_dirty(a)
}

@(private)
app_follow_bottom :: proc(a: ^App) {
	a.follow = true
	a.scroll = 0
	app_mark_dirty(a)
}

@(private)
app_improve_prompt :: proc(a: ^App) {
	if a.session.busy || a.improving {
		return
	}
	draft := strings.trim_space(strings.to_string(a.input))
	if len(draft) == 0 {
		session.session_set_status(&a.session, "type a prompt first, then F2 /improve")
		app_mark_dirty(a)
		return
	}
	p := provider.registry_active(&a.registry)
	if p == nil {
		session.session_set_status(&a.session, "no provider")
		return
	}
	a.improving = true
	a.improve_gen += 1
	gen := a.improve_gen
	session.session_set_status(&a.session, "improving prompt...")
	app_mark_dirty(a)
	job := new(Improve_Job)
	job.app = a
	job.gen = gen
	job.draft = strings.clone(draft)
	job.prov = p^
	job.prov.base_url = strings.clone(p.base_url)
	job.prov.api_key = strings.clone(p.api_key)
	job.prov.default_model = strings.clone(p.default_model)
	thread.run_with_data(job, improve_job)
}

Improve_Job :: struct {
	app:   ^App,
	gen:   u64,
	draft: string,
	prov:  provider.Provider,
}

@(private)
improve_job :: proc(data: rawptr) {
	args := cast(^Improve_Job)data
	defer {
		delete(args.draft)
		provider.provider_destroy(&args.prov)
		free(args)
	}
	improved, err := agent.improve_prompt(&args.prov, args.draft)
	a := args.app
	sync.mutex_lock(&a.improve_pending_mu)
	delete(a.improve_pending_text)
	delete(a.improve_pending_err)
	a.improve_pending_text = ""
	a.improve_pending_err = ""
	if len(err) > 0 {
		a.improve_pending_err = strings.clone(err)
		delete(err)
		delete(improved)
	} else {
		a.improve_pending_text = improved
		a.improve_pending_err = ""
	}
	a.improve_pending_gen = args.gen
	a.improve_pending = true
	sync.mutex_unlock(&a.improve_pending_mu)
}

app_apply_improve_pending :: proc(a: ^App) -> bool {
	sync.mutex_lock(&a.improve_pending_mu)
	if !a.improve_pending {
		sync.mutex_unlock(&a.improve_pending_mu)
		return false
	}
	gen := a.improve_pending_gen
	text := a.improve_pending_text
	err := a.improve_pending_err
	a.improve_pending_text = ""
	a.improve_pending_err = ""
	a.improve_pending = false
	sync.mutex_unlock(&a.improve_pending_mu)

	a.improving = false
	if gen != a.improve_gen {
		delete(text)
		delete(err)
		return true
	}
	if len(err) > 0 {
		session.session_set_status(&a.session, fmt.tprintf("improve failed: %s", err))
		delete(err)
		delete(text)
		app_mark_dirty(a)
		return true
	}
	draft := strings.to_string(a.input)
	delete(a.improve_undo)
	a.improve_undo = strings.clone(draft)
	strings.builder_reset(&a.input)
	strings.write_string(&a.input, text)
	a.cursor = len(text)
	delete(text)
	session.session_set_status(&a.session, "prompt improved (ctrl-z undo, enter to send)")
	app_mark_dirty(a)
	return true
}

@(private)
app_undo_improve :: proc(a: ^App) {
	if len(a.improve_undo) == 0 {
		session.session_set_status(&a.session, "nothing to undo")
		app_mark_dirty(a)
		return
	}
	strings.builder_reset(&a.input)
	strings.write_string(&a.input, a.improve_undo)
	a.cursor = len(a.improve_undo)
	delete(a.improve_undo)
	a.improve_undo = ""
	session.session_set_status(&a.session, "undid prompt improve")
	app_mark_dirty(a)
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
