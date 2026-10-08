// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
TUI renderer and input handler for Kind.View custom forms.
*/

package app

import "core:fmt"
import "core:strings"
import "core:unicode/utf8"
import "nullray:ask"
import "nullray:ui"

app_view_form_clear :: proc(a: ^App) {
	ask.view_def_destroy(&a.view_form)
	a.view_form = {}
	a.view_form_focus = 0
	a.view_form_err = {}
	delete(a.view_form_err)
	a.view_form_err = {}
	a.view_form_scroll = 0
	a.view_form_active = false
}

app_ask_clear_full :: proc(a: ^App) {
	app_ask_clear(a)
	app_view_form_clear(a)
}

// Extended poll: when the pending challenge is a View, load the schema.
app_ask_poll_views :: proc(a: ^App) -> bool {
	active, id, kind, prompt, options, free_form, view_json := ask.challenge_pending_ex()
	if !active {
		delete(view_json)
		if a.ask_active || a.view_form_active {
			app_ask_clear_full(a)
			return true
		}
		return false
	}
	changed := false
	if kind == .View {
		if !a.view_form_active || a.ask_id != id {
			app_ask_clear_full(a)
			a.ask_active = true
			a.view_form_active = true
			a.ask_id = id
			a.ask_kind = .View
			a.ask_prompt = prompt
			// prompt already owned
			def, perr := ask.view_parse(view_json, context.allocator)
			delete(view_json)
			if perr != "" {
				// Bad schema at fulfill time: cancel with message baked in status.
				a.view_form_err = perr
				// Still show a minimal modal so Esc works.
				a.view_form = ask.View_Def{
					title = strings.clone("Invalid view"),
					body = strings.clone(perr),
				}
				a.view_form.actions = make([dynamic]ask.View_Action)
				append(&a.view_form.actions, ask.View_Action{
					id = strings.clone("cancel"),
					label = strings.clone("Close"),
					kind = .Cancel,
				})
			} else {
				a.view_form = def
			}
			a.view_form_focus = 0
			a.view_form_scroll = 0
			changed = true
		} else {
			delete(prompt)
			delete(view_json)
		}
		for o in options {
			delete(o)
		}
		delete(options)
		_ = free_form
		return changed
	}
	// Non-view: fall through to classic ask poll semantics using already-fetched data.
	delete(view_json)
	if a.view_form_active {
		app_view_form_clear(a)
	}
	if !a.ask_active || a.ask_id != id {
		app_ask_clear(a)
		a.ask_active = true
		a.ask_id = id
		a.ask_kind = kind
		a.ask_prompt = prompt
		a.ask_options = make([dynamic]string)
		for o in options {
			append(&a.ask_options, strings.clone(o))
		}
		for o in options {
			delete(o)
		}
		delete(options)
		a.ask_free = free_form
		a.ask_sel = 0
		changed = true
	} else {
		delete(prompt)
		for o in options {
			delete(o)
		}
		delete(options)
	}
	return changed
}

app_view_form_submit :: proc(a: ^App, action_i: int) {
	if action_i < 0 || action_i >= len(a.view_form.actions) {
		return
	}
	act := a.view_form.actions[action_i]
	if act.kind == .Cancel {
		_ = ask.cancel(a.ask_id)
		app_ask_clear_full(a)
		app_mark_dirty(a)
		return
	}
	if msg := ask.view_validate(&a.view_form, context.allocator); len(msg) > 0 {
		delete(a.view_form_err)
		a.view_form_err = msg
		app_mark_dirty(a)
		return
	}
	payload := ask.view_result_json(&a.view_form, act.id, context.allocator)
	_ = ask.fulfill(a.ask_id, payload)
	delete(payload)
	app_ask_clear_full(a)
	app_mark_dirty(a)
}

app_view_form_on_event :: proc(a: ^App, ev: ui.Event) -> bool {
	if !a.view_form_active {
		return false
	}
	if ev.kind == .Ctrl_Q {
		return true
	}
	if ev.kind == .Ctrl_C || ev.kind == .Esc {
		_ = ask.cancel(a.ask_id)
		app_ask_clear_full(a)
		app_mark_dirty(a)
		return false
	}

	total := ask.view_focusable_count(&a.view_form)
	if total <= 0 {
		if ev.kind == .Enter {
			// OK on body-only showcase.
			if len(a.view_form.actions) > 0 {
				app_view_form_submit(a, 0)
			}
		}
		return false
	}

	#partial switch ev.kind {
	case .Up:
		if a.view_form_focus > 0 {
			a.view_form_focus -= 1
		} else {
			a.view_form_focus = total - 1
		}
		app_mark_dirty(a)
		return false
	case .Down, .Tab:
		a.view_form_focus = (a.view_form_focus + 1) % total
		app_mark_dirty(a)
		return false
	case .Enter:
		fi, ai, is_act := ask.view_focus_resolve(&a.view_form, a.view_form_focus)
		if is_act {
			app_view_form_submit(a, ai)
			return false
		}
		if fi >= 0 && fi < len(a.view_form.fields) {
			f := &a.view_form.fields[fi]
			if f.kind == .Checkbox {
				f.checked = !f.checked
				app_mark_dirty(a)
				return false
			}
			// Enter on a field jumps to the primary action.
			for a_i in 0 ..< len(a.view_form.actions) {
				if a.view_form.actions[a_i].primary || a.view_form.actions[a_i].kind == .Submit {
					// move focus then submit
					// find focus index of this action
					idx := 0
					for ff in a.view_form.fields {
						#partial switch ff.kind {
						case .Label, .Markdown, .Separator:
						case:
							idx += 1
						}
					}
					a.view_form_focus = idx + a_i
					app_view_form_submit(a, a_i)
					return false
				}
			}
		}
		return false
	case .Left, .Right:
		fi, _, is_act := ask.view_focus_resolve(&a.view_form, a.view_form_focus)
		if is_act {
			// cycle actions with left/right
			if total > 0 {
				if ev.kind == .Left {
					if a.view_form_focus > 0 {
						a.view_form_focus -= 1
					}
				} else {
					a.view_form_focus = (a.view_form_focus + 1) % total
				}
				app_mark_dirty(a)
			}
			return false
		}
		if fi >= 0 && fi < len(a.view_form.fields) {
			f := &a.view_form.fields[fi]
			if f.kind == .Select || f.kind == .Radio {
				if len(f.options) == 0 {
					return false
				}
				if ev.kind == .Left {
					if f.sel > 0 {
						f.sel -= 1
					} else {
						f.sel = len(f.options) - 1
					}
				} else {
					f.sel = (f.sel + 1) % len(f.options)
				}
				delete(f.value)
				f.value = strings.clone(f.options[f.sel])
				app_mark_dirty(a)
			}
		}
		return false
	case .Backspace:
		fi, _, is_act := ask.view_focus_resolve(&a.view_form, a.view_form_focus)
		if is_act || fi < 0 {
			return false
		}
		f := &a.view_form.fields[fi]
		#partial switch f.kind {
		case .Text, .Textarea, .Number, .Password:
			if len(f.value) > 0 {
				_, size := utf8.decode_last_rune_in_string(f.value)
				if size > 0 {
					new_s := strings.clone(f.value[:len(f.value) - size])
					delete(f.value)
					f.value = new_s
					app_mark_dirty(a)
				}
			}
		}
		return false
	case .Rune:
		fi, _, is_act := ask.view_focus_resolve(&a.view_form, a.view_form_focus)
		if is_act || fi < 0 {
			return false
		}
		f := &a.view_form.fields[fi]
		// Space toggles checkboxes without inserting text.
		if ev.ch == ' ' && f.kind == .Checkbox {
			f.checked = !f.checked
			app_mark_dirty(a)
			return false
		}
		if ev.ch < 0x20 {
			return false
		}
		#partial switch f.kind {
		case .Text, .Textarea, .Number, .Password:
			if utf8.rune_count_in_string(f.value) >= ask.VIEW_MAX_VALUE {
				return false
			}
			if f.kind == .Number {
				// Allow digits, minus, dot only.
				if !(ev.ch == '-' || ev.ch == '.' || (ev.ch >= '0' && ev.ch <= '9')) {
					return false
				}
			}
			b: strings.Builder
			strings.builder_init(&b)
			strings.write_string(&b, f.value)
			strings.write_rune(&b, ev.ch)
			nstr := strings.clone(strings.to_string(b))
			strings.builder_destroy(&b)
			delete(f.value)
			f.value = nstr
			app_mark_dirty(a)
		}
		return false
	}
	return false
}

app_draw_view_form_modal :: proc(buf: ^ui.Buffer, a: ^App) {
	if !a.view_form_active {
		return
	}
	t := ui.theme()
	w := min(78, buf.width - 2)
	if w < 20 {
		w = max(10, buf.width - 2)
	}
	inner_w := max(1, w - 4)
	h := min(buf.height - 1, max(10, buf.height - 2))
	x := max(0, (buf.width - w) / 2)
	y := max(0, (buf.height - h) / 2)
	title := a.view_form.title
	if len(title) == 0 {
		title = "View"
	}
	ui.draw_box(buf, x, y, w, h, t.accent, t.bg, title)

	// Build display rows: body lines, fields, actions, error, hint.
	content_top := y + 1
	content_bot := y + h - 2
	row := content_top

	// Body
	if len(a.view_form.body) > 0 {
		lines := ui.word_wrap_lines(a.view_form.body, inner_w, context.temp_allocator)
		max_body := min(len(lines), 6)
		for i in 0 ..< max_body {
			if row >= content_bot {
				break
			}
			ui.buffer_text_clip(buf, x + 2, row, x + w - 2, lines[i], t.fg, t.bg)
			row += 1
		}
		if row < content_bot {
			row += 1 // gap
		}
	}

	// Fields
	focus_idx := 0
	for f, fi in a.view_form.fields {
		if row >= content_bot - 1 {
			break
		}
		#partial switch f.kind {
		case .Separator:
			ui.buffer_hline(buf, x + 2, row, inner_w, '─', t.border, t.bg)
			row += 1
			continue
		case .Label, .Markdown:
			lines := ui.word_wrap_lines(f.label, inner_w, context.temp_allocator)
			if len(f.value) > 0 {
				// markdown/body content sometimes in value
				lines = ui.word_wrap_lines(len(f.label) > 0 ? f.label : f.value, inner_w, context.temp_allocator)
			}
			for ln in lines {
				if row >= content_bot - 1 {
					break
				}
				ui.buffer_text_clip(buf, x + 2, row, x + w - 2, ln, t.muted, t.bg)
				row += 1
			}
			continue
		case:
		}

		is_focus := false
		{
			ff, _, is_act := ask.view_focus_resolve(&a.view_form, a.view_form_focus)
			is_focus = !is_act && ff == fi
		}
		_ = focus_idx
		label := f.label
		if f.required {
			label = fmt.tprintf("%s *", label)
		}
		mark := is_focus ? "> " : "  "
		fg := is_focus ? t.accent : t.fg
		line := ""
		switch f.kind {
		case .Checkbox:
			box := f.checked ? "[x]" : "[ ]"
			line = fmt.tprintf("%s%s %s", mark, box, label)
		case .Select, .Radio:
			cur := ""
			if f.sel >= 0 && f.sel < len(f.options) {
				cur = f.options[f.sel]
			}
			line = fmt.tprintf("%s%s: <%s>  (Left/Right)", mark, label, cur)
		case .Password:
			n := utf8.rune_count_in_string(f.value)
			stars, _ := strings.repeat("*", min(n, 24), context.temp_allocator)
			line = fmt.tprintf("%s%s: %s_", mark, label, stars)
		case .Text, .Textarea, .Number:
			shown := f.value
			if len(shown) == 0 && len(f.placeholder) > 0 && !is_focus {
				shown = f.placeholder
				fg = t.muted
			}
			suffix := is_focus ? "_" : ""
			line = fmt.tprintf("%s%s: %s%s", mark, label, shown, suffix)
		case .Label, .Markdown, .Separator:
			line = fmt.tprintf("%s%s", mark, label)
		}
		ui.buffer_text_clip(buf, x + 2, row, x + w - 2, line, fg, t.bg)
		row += 1
		// count focusable
		focus_idx += 1
	}

	// Actions row
	if row < content_bot {
		row += 1
	}
	if row < content_bot {
		ab: strings.Builder
		strings.builder_init(&ab, context.temp_allocator)
		for act, ai in a.view_form.actions {
			_, aai, is_act := ask.view_focus_resolve(&a.view_form, a.view_form_focus)
			hot := is_act && aai == ai
			if ai > 0 {
				strings.write_string(&ab, "  ")
			}
			if hot {
				strings.write_string(&ab, "[")
				strings.write_string(&ab, act.label)
				strings.write_string(&ab, "]")
			} else {
				strings.write_string(&ab, " ")
				strings.write_string(&ab, act.label)
				strings.write_string(&ab, " ")
			}
		}
		ui.buffer_text_clip(buf, x + 2, row, x + w - 2, strings.to_string(ab), t.accent, t.bg)
		row += 1
	}

	// Error
	if len(a.view_form_err) > 0 && row < content_bot {
		ui.buffer_text_clip(buf, x + 2, row, x + w - 2, a.view_form_err, t.error, t.bg)
	}

	hint := "Tab fields · Enter submit · Space check · Esc cancel"
	ui.buffer_text_clip(buf, x + 2, y + h - 2, x + w - 2, hint, t.muted, t.bg)
}
