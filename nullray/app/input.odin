/*
Input events, editing, scroll, prompt improve, submit.
*/

package app

import "core:fmt"
import "core:strings"
import "core:thread"
import "nullray:agent"
import "nullray:config"
import "nullray:constants"
import "nullray:provider"
import "nullray:session"
import "nullray:ui"

app_toggle_help :: proc(a: ^App) {
	a.show_help = !a.show_help
	app_mark_dirty(a)
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
		// Timer-only splash. Drop input so typed keys are not applied after it ends.
		return false
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
		return false
	}

	if ev.kind == .Mouse_Press && ev.my == 0 && ev.mx >= a.help_btn_x {
		app_toggle_help(a)
		return false
	}

	suggesting := len(slash_matches(strings.to_string(a.input))) > 0

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
			strings.builder_reset(&a.input)
			a.cursor = 0
			a.suggest_sel = 0
			app_mark_dirty(a)
			return false
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
		return true
	case .Help:
		app_toggle_help(a)
		return false
	case .Clear_Chat:
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
		app_refresh_credits(a)
		p := provider.registry_active(&a.registry)
		if p != nil {
			session.session_remember_model(&a.session, p.id, p.default_model)
			msg := fmt.tprintf("provider %s", p.name)
			if len(a.credits_label) > 0 {
				msg = fmt.tprintf("%s · %s", msg, a.credits_label)
			}
			session.session_set_status(&a.session, msg)
		}
		app_mark_dirty(a)
		return false
	case .Provider_Prev:
		provider.registry_cycle(&a.registry, -1)
		app_refresh_credits(a)
		p := provider.registry_active(&a.registry)
		if p != nil {
			session.session_remember_model(&a.session, p.id, p.default_model)
			msg := fmt.tprintf("provider %s", p.name)
			if len(a.credits_label) > 0 {
				msg = fmt.tprintf("%s · %s", msg, a.credits_label)
			}
			session.session_set_status(&a.session, msg)
		}
		app_mark_dirty(a)
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
			app_scroll_by(a, 1)
		}
		return false
	case .Scroll_Down:
		if !suggesting {
			app_scroll_by(a, -1)
		}
		return false
	case .Page_Up:
		app_scroll_by(a, max(8, a.loop.term.height / 2))
		return false
	case .Page_Down:
		app_scroll_by(a, -max(8, a.loop.term.height / 2))
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
			app_mark_dirty(a)
		}
		return false
	case .None:
	}

	if a.session.busy && ev.kind == .Esc {
		session.session_request_cancel(&a.session)
		app_mark_dirty(a)
		return false
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
		if a.cursor > 0 && len(text) > 0 {
			cut := a.cursor - 1
			left := text[:cut]
			right := text[a.cursor:]
			strings.builder_reset(&a.input)
			strings.write_string(&a.input, left)
			strings.write_string(&a.input, right)
			a.cursor = cut
			a.suggest_sel = 0
			app_mark_dirty(a)
		}
	case .Left:
		if a.cursor > 0 {
			a.cursor -= 1
			app_mark_dirty(a)
		}
	case .Right:
		if a.cursor < len(strings.to_string(a.input)) {
			a.cursor += 1
			app_mark_dirty(a)
		}
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
		if ev.my >= a.loop.term.height - 3 {
			app_follow_bottom(a)
		}
	case .Rune:
		if (!a.session.busy || a.pasting) && ev.ch >= 0x20 {
			app_insert_rune(a, ev.ch)
		}
	case .Esc:
		if len(strings.to_string(a.input)) > 0 {
			strings.builder_reset(&a.input)
			a.cursor = 0
			a.suggest_sel = 0
			app_mark_dirty(a)
		}
	}
	return false
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
			if a.cursor > 0 {
				a.cursor -= 1
				app_mark_dirty(a)
			}
			return true
		case .Ctrl_F:
			if a.cursor < len(strings.to_string(a.input)) {
				a.cursor += 1
				app_mark_dirty(a)
			}
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
	if a.cursor <= 0 || len(text) == 0 {
		return
	}
	i := a.cursor
	for i > 0 && text[i - 1] == ' ' {
		i -= 1
	}
	for i > 0 && text[i - 1] != ' ' {
		i -= 1
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
	if a.cursor >= len(text) {
		return
	}
	left := text[:a.cursor]
	right := text[a.cursor + 1:]
	strings.builder_reset(&a.input)
	strings.write_string(&a.input, left)
	strings.write_string(&a.input, right)
	a.suggest_sel = 0
	app_mark_dirty(a)
}

@(private)
app_insert_text :: proc(a: ^App, s: string) {
	text := strings.to_string(a.input)
	if len(text)+len(s) > constants.MAX_INPUT_CHARS {
		return
	}
	left := text[:a.cursor]
	right := text[a.cursor:]
	strings.builder_reset(&a.input)
	strings.write_string(&a.input, left)
	strings.write_string(&a.input, s)
	strings.write_string(&a.input, right)
	a.cursor += len(s)
	a.suggest_sel = 0
	app_mark_dirty(a)
}

@(private)
app_insert_rune :: proc(a: ^App, ch: rune) {
	text := strings.to_string(a.input)
	if len(text) >= constants.MAX_INPUT_CHARS {
		return
	}
	left := text[:a.cursor]
	right := text[a.cursor:]
	strings.builder_reset(&a.input)
	strings.write_string(&a.input, left)
	strings.write_rune(&a.input, ch)
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
	session.session_set_status(&a.session, "improving prompt...")
	app_mark_dirty(a)
	job := new(Improve_Job)
	job.app = a
	job.draft = strings.clone(draft)
	job.prov = p^
	job.prov.base_url = strings.clone(p.base_url)
	job.prov.api_key = strings.clone(p.api_key)
	job.prov.default_model = strings.clone(p.default_model)
	thread.run_with_data(job, improve_job)
}

Improve_Job :: struct {
	app:   ^App,
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
	a.improving = false
	if len(err) > 0 {
		session.session_set_status(&a.session, fmt.tprintf("improve failed: %s", err))
		delete(err)
		delete(improved)
		a.dirty = true
		return
	}
	delete(a.improve_undo)
	a.improve_undo = strings.clone(args.draft)
	strings.builder_reset(&a.input)
	strings.write_string(&a.input, improved)
	a.cursor = len(improved)
	delete(improved)
	session.session_set_status(&a.session, "prompt improved (ctrl-z undo, enter to send)")
	a.dirty = true
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
	if a.session.busy {
		return
	}
	text := strings.trim_space(strings.to_string(a.input))
	if len(text) == 0 {
		return
	}
	strings.builder_reset(&a.input)
	a.cursor = 0
	a.scroll = 0
	a.follow = true

	if app_handle_slash(a, text) {
		app_mark_dirty(a)
		return
	}

	session.session_push_user(&a.session, text)
	p := provider.registry_active(&a.registry)
	session.session_start_chat(&a.session, p)
	app_mark_dirty(a)
}


