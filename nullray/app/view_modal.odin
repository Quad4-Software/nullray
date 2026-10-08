// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
TUI renderer and input handler for Kind.View custom forms.
*/

package app

import "core:encoding/json"
import "core:fmt"
import "core:strings"
import "core:unicode/utf8"
import "nullray:ask"
import "nullray:tools"
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

// Render form state into the side pane as a text canvas (panel placement).
app_view_form_seed_canvas :: proc(a: ^App) {
	title := a.view_form.title
	if len(title) == 0 {
		title = "Canvas"
	}
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	if len(a.view_form.body) > 0 {
		strings.write_string(&b, a.view_form.body)
		strings.write_string(&b, "\n\n")
	}
	for f in a.view_form.fields {
		#partial switch f.kind {
		case .Separator:
			strings.write_string(&b, "----------\n")
		case .Label, .Markdown:
			strings.write_string(&b, f.label)
			strings.write_byte(&b, '\n')
		case .Image:
			src := len(f.src) > 0 ? f.src : f.default
			fmt.sbprintf(&b, "[img] %s\n", src)
		case .Checkbox:
			fmt.sbprintf(&b, "[%s] %s\n", f.checked ? "x" : " ", f.label)
		case .Password:
			fmt.sbprintf(&b, "%s: ****\n", f.label)
		case .Select, .Radio:
			cur := f.value
			if f.sel >= 0 && f.sel < len(f.options) {
				cur = f.options[f.sel]
			}
			fmt.sbprintf(&b, "%s: %s\n", f.label, cur)
		case:
			fmt.sbprintf(&b, "%s: %s\n", f.label, f.value)
		}
	}
	if len(a.view_form.actions) > 0 {
		strings.write_string(&b, "\nActions: ")
		for act, i in a.view_form.actions {
			if i > 0 {
				strings.write_string(&b, " | ")
			}
			strings.write_string(&b, act.label)
		}
		strings.write_byte(&b, '\n')
	}
	strings.write_string(&b, "\n(interactive controls still on the modal; Esc cancels)")
	_ = app_view_open_text(a, title, strings.to_string(b))
	if len(a.view_form.image) > 0 {
		_ = app_view_open(a, a.view_form.image)
	}
}

// Drop non-ASCII when the form disables emoji (keeps latin and common ASCII).
view_strip_non_ascii :: proc(s: string, allocator := context.temp_allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	for r in s {
		if r <= 0x7f {
			strings.write_rune(&b, r)
		} else {
			strings.write_byte(&b, '?')
		}
	}
	return strings.to_string(b)
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
				// Larger UIs dock as a live canvas in the side pane.
				if a.view_form.placement == .Panel {
					app_view_form_seed_canvas(a)
				} else if len(a.view_form.image) > 0 {
					_ = app_view_open(a, a.view_form.image)
				}
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
	if act.kind == .Script {
		app_view_form_run_script(a, act.script)
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

// Run a script action: workspace-relative shell with a tight timeout.
// stdout is shown as the form error/status line so the agent-authored script
// can feed feedback without leaving the UI.
app_view_form_run_script :: proc(a: ^App, script: string) {
	cmd := strings.trim_space(script)
	if len(cmd) == 0 {
		delete(a.view_form_err)
		a.view_form_err = strings.clone("empty script")
		app_mark_dirty(a)
		return
	}
	// Hard guard: block obvious network/destructive tokens.
	low := strings.to_lower(cmd, context.temp_allocator)
	blocked := []string{"curl ", "wget ", "nc ", "ncat ", "rm -rf", "mkfs", "dd if=", ":(){"}
	for bad in blocked {
		if strings.contains(low, bad) {
			delete(a.view_form_err)
			a.view_form_err = strings.clone("script blocked by safety guard")
			app_mark_dirty(a)
			return
		}
	}
	// Prefer sh -c so simple agent scripts work without a full shell tool.
	out, err := tools.run_capture_argv([]string{"sh", "-c", cmd}, context.temp_allocator)
	msg := ""
	if len(err) > 0 {
		msg = err
	} else {
		msg = strings.trim_space(out)
		if len(msg) == 0 {
			msg = "ok"
		}
	}
	if len(msg) > ask.VIEW_SCRIPT_MAX_OUTPUT {
		msg = msg[:ask.VIEW_SCRIPT_MAX_OUTPUT]
	}
	// Best-effort: if stdout is JSON object of field id -> value, apply it.
	if strings.has_prefix(msg, "{") {
		app_view_form_apply_json_values(a, msg)
	}
	delete(a.view_form_err)
	a.view_form_err = strings.clone(msg)
	if len(a.view_form_err) > 240 {
		trimmed := strings.clone(a.view_form_err[:240])
		delete(a.view_form_err)
		a.view_form_err = trimmed
	}
	app_mark_dirty(a)
}

app_view_form_apply_json_values :: proc(a: ^App, raw: string) {
	// Lightweight id:value apply for script feedback. Uses the same parse path
	// fields expect: set text values and checkbox bools when keys match.
	doc, perr := json.parse_string(raw, .JSON, allocator = context.temp_allocator)
	if perr != .None {
		return
	}
	obj, ok := doc.(json.Object)
	if !ok {
		return
	}
	for &f in a.view_form.fields {
		v, has := obj[f.id]
		if !has {
			continue
		}
		#partial switch f.kind {
		case .Checkbox:
			if b, bok := v.(json.Boolean); bok {
				f.checked = bool(b)
			}
		case .Text, .Textarea, .Number, .Password:
			s := ""
			if js, jok := v.(json.String); jok {
				s = string(js)
			} else if n, nok := ask.json_number_value(v); nok {
				s = fmt.tprintf("%v", n)
			}
			delete(f.value)
			f.value = strings.clone(s)
		case .Select, .Radio:
			s := ""
			if js, jok := v.(json.String); jok {
				s = string(js)
			}
			for o, oi in f.options {
				if o == s {
					f.sel = oi
					delete(f.value)
					f.value = strings.clone(o)
					break
				}
			}
		}
	}
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
	// Per-view color overrides (agent-styled modal).
	box_fg := t.fg
	box_bg := t.bg
	box_accent := t.accent
	box_border := t.border
	if c, ok := ui.color_parse(a.view_form.fg); ok {
		box_fg = c
	}
	if c, ok := ui.color_parse(a.view_form.bg); ok {
		box_bg = c
	}
	if c, ok := ui.color_parse(a.view_form.accent); ok {
		box_accent = c
	}
	if c, ok := ui.color_parse(a.view_form.border); ok {
		box_border = c
	}
	// Agent-requested size, clamped to the terminal with a usable minimum.
	want_w := a.view_form.width
	want_h := a.view_form.height
	if want_w <= 0 {
		want_w = 78
	}
	if want_h <= 0 {
		want_h = max(10, buf.height / 2)
	}
	w := min(want_w, buf.width - 2)
	if w < 20 {
		w = max(10, buf.width - 2)
	}
	inner_w := max(1, w - 4)
	h := min(want_h, buf.height - 1)
	if h < 8 {
		h = min(8, buf.height)
	}
	if h > buf.height {
		h = buf.height
	}
	x := max(0, (buf.width - w) / 2)
	y := max(0, (buf.height - h) / 2)
	title := a.view_form.title
	if len(title) == 0 {
		title = "View"
	}
	if !a.view_form.emoji {
		title = view_strip_non_ascii(title, context.temp_allocator)
	}
	ui.draw_box(buf, x, y, w, h, box_accent, box_bg, title)
	_ = box_border
	_ = box_fg

	// Build display rows: body lines, fields, actions, error, hint.
	content_top := y + 1
	content_bot := y + h - 2
	row := content_top

	// Body
	if len(a.view_form.body) > 0 {
		body := a.view_form.body
		if !a.view_form.emoji {
			body = view_strip_non_ascii(body, context.temp_allocator)
		}
		lines := ui.word_wrap_lines(body, inner_w, context.temp_allocator)
		// Scale body lines with modal height.
		max_body := min(len(lines), max(3, h / 4))
		for i in 0 ..< max_body {
			if row >= content_bot {
				break
			}
			ui.buffer_text_clip(buf, x + 2, row, x + w - 2, lines[i], box_fg, box_bg)
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
		case .Image:
			src := f.src
			if len(src) == 0 {
				src = f.default
			}
			line := fmt.tprintf("  [img] %s", len(src) > 0 ? src : f.label)
			ui.buffer_text_clip(buf, x + 2, row, x + w - 2, line, t.muted, t.bg)
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
		#partial switch f.kind {
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
		case .Image:
			src := f.src
			if len(src) == 0 {
				src = f.default
			}
			line = fmt.tprintf("%s[img] %s", mark, len(src) > 0 ? src : label)
		case .Label, .Markdown, .Separator:
			line = fmt.tprintf("%s%s", mark, label)
		}
		if !a.view_form.emoji {
			line = view_strip_non_ascii(line, context.temp_allocator)
		}
		ui.buffer_text_clip(buf, x + 2, row, x + w - 2, line, fg, box_bg)
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
			lab := act.label
			if !a.view_form.emoji {
				lab = view_strip_non_ascii(lab, context.temp_allocator)
			}
			if hot {
				strings.write_string(&ab, "[")
				strings.write_string(&ab, lab)
				strings.write_string(&ab, "]")
			} else {
				strings.write_string(&ab, " ")
				strings.write_string(&ab, lab)
				strings.write_string(&ab, " ")
			}
		}
		ui.buffer_text_clip(buf, x + 2, row, x + w - 2, strings.to_string(ab), box_accent, box_bg)
		row += 1
	}

	// Error
	if len(a.view_form_err) > 0 && row < content_bot {
		ui.buffer_text_clip(buf, x + 2, row, x + w - 2, a.view_form_err, t.error, box_bg)
	}

	hint := "Tab fields · Enter submit · Space check · Esc cancel"
	ui.buffer_text_clip(buf, x + 2, y + h - 2, x + w - 2, hint, t.muted, box_bg)
}
