// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
TUI modal for ask_question and ask_secret challenges. Mirrors the
elevate askpass channel: the tool blocks on a condvar while this modal
fulfills or cancels.
*/

package app

import "core:fmt"
import "core:strings"
import "core:unicode/utf8"
import "nullray:ask"
import "nullray:elevate"
import "nullray:ui"

app_ask_clear :: proc(a: ^App) {
	a.ask_active = false
	a.ask_id = 0
	a.ask_kind = .Text
	a.ask_free = false
	a.ask_editing = false
	a.ask_sel = 0
	delete(a.ask_prompt)
	a.ask_prompt = {}
	for o in a.ask_options {
		delete(o)
	}
	delete(a.ask_options)
	a.ask_options = nil
	if len(a.ask_buf) > 0 {
		elevate.zero_and_delete(a.ask_buf)
	}
	a.ask_buf = {}
}

app_ask_poll :: proc(a: ^App) -> bool {
	active, id, kind, prompt, options, free_form := ask.challenge_pending()
	if !active {
		if a.ask_active {
			app_ask_clear(a)
			return true
		}
		return false
	}
	changed := false
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

app_ask_rows :: proc(a: ^App) -> int {
	n := len(a.ask_options)
	if a.ask_kind == .Choice && a.ask_free {
		n += 1
	}
	return n
}

app_ask_submit_buf :: proc(a: ^App) {
	if len(a.ask_buf) == 0 {
		return
	}
	buf := a.ask_buf
	a.ask_buf = {}
	_ = ask.fulfill(a.ask_id, buf)
	elevate.zero_and_delete(buf)
	app_ask_clear(a)
	app_mark_dirty(a)
}

app_ask_on_event :: proc(a: ^App, ev: ui.Event) -> bool {
	if !a.ask_active {
		return false
	}
	if ev.kind == .Ctrl_Q {
		return true
	}
	if ev.kind == .Ctrl_C {
		_ = ask.cancel(a.ask_id)
		app_ask_clear(a)
		app_mark_dirty(a)
		return false
	}

	// Free-text entry inside a choice prompt or the plain text/secret path.
	text_entry := a.ask_kind != .Choice || a.ask_editing
	if ev.kind == .Esc {
		if a.ask_kind == .Choice && a.ask_editing {
			a.ask_editing = false
			if len(a.ask_buf) > 0 {
				elevate.zero_and_delete(a.ask_buf)
				a.ask_buf = {}
			}
			app_mark_dirty(a)
			return false
		}
		_ = ask.cancel(a.ask_id)
		app_ask_clear(a)
		app_mark_dirty(a)
		return false
	}

	if a.ask_kind == .Confirm && !a.ask_editing {
		if ev.kind == .Rune && (ev.ch == 'y' || ev.ch == 'Y') {
			_ = ask.fulfill(a.ask_id, "yes")
			app_ask_clear(a)
			app_mark_dirty(a)
			return false
		}
		if ev.kind == .Rune && (ev.ch == 'n' || ev.ch == 'N') {
			_ = ask.fulfill(a.ask_id, "no")
			app_ask_clear(a)
			app_mark_dirty(a)
			return false
		}
	}

	if a.ask_kind == .Choice && !a.ask_editing {
		rows := app_ask_rows(a)
		#partial switch ev.kind {
		case .Up:
			if a.ask_sel > 0 {
				a.ask_sel -= 1
			} else {
				a.ask_sel = rows - 1
			}
			app_mark_dirty(a)
		case .Down:
			a.ask_sel = (a.ask_sel + 1) % max(1, rows)
			app_mark_dirty(a)
		case .Enter:
			if a.ask_sel < len(a.ask_options) {
				_ = ask.fulfill(a.ask_id, a.ask_options[a.ask_sel])
				app_ask_clear(a)
			} else {
				a.ask_editing = true
			}
			app_mark_dirty(a)
		case .Rune:
			if ev.ch >= '1' && ev.ch <= '9' {
				idx := int(ev.ch - '1')
				if idx < len(a.ask_options) {
					_ = ask.fulfill(a.ask_id, a.ask_options[idx])
					app_ask_clear(a)
					app_mark_dirty(a)
				}
			}
		}
		return false
	}

	if text_entry {
		#partial switch ev.kind {
		case .Enter:
			app_ask_submit_buf(a)
		case .Backspace:
			if len(a.ask_buf) > 0 {
				_, size := utf8.decode_last_rune_in_string(a.ask_buf)
				if size > 0 {
					new_s := strings.clone(a.ask_buf[:len(a.ask_buf) - size])
					elevate.zero_and_delete(a.ask_buf)
					a.ask_buf = new_s
					app_mark_dirty(a)
				}
			}
		case .Rune:
			if ev.ch >= 0x20 {
				b: strings.Builder
				strings.builder_init(&b)
				strings.write_string(&b, a.ask_buf)
				strings.write_rune(&b, ev.ch)
				nstr := strings.clone(strings.to_string(b))
				strings.builder_destroy(&b)
				if len(a.ask_buf) > 0 {
					elevate.zero_and_delete(a.ask_buf)
				}
				a.ask_buf = nstr
				app_mark_dirty(a)
			}
		}
	}
	return false
}

app_draw_ask_modal :: proc(buf: ^ui.Buffer, a: ^App) {
	if !a.ask_active {
		return
	}
	t := ui.theme()
	w := min(72, max(44, buf.width - 4))
	rows := app_ask_rows(a)
	h := 8 + min(rows, 9)
	x := max(0, (buf.width - w) / 2)
	y := max(1, (buf.height - h) / 2)
	title := "Question"
	if a.ask_kind == .Secret {
		title = "Secret input"
	} else if a.ask_kind == .Confirm {
		title = "Confirm"
	} else if a.ask_kind == .Choice {
		title = "Choose an option"
	}
	ui.draw_box(buf, x, y, w, h, t.accent, t.bg, title)
	ui.buffer_text_clip(buf, x + 2, y + 2, x + w - 2, a.ask_prompt, t.fg, t.bg)

	row_y := y + 4
	if a.ask_kind == .Choice && !a.ask_editing {
		max_opts := min(rows, 9)
		top := 0
		if a.ask_sel >= max_opts {
			top = a.ask_sel - max_opts + 1
		}
		for i in top ..< top + max_opts {
			is_custom := i >= len(a.ask_options)
			label := ""
			if is_custom {
				label = "Other (type answer)"
			} else {
				label = a.ask_options[i]
			}
			line := fmt.tprintf("%d. %s", i + 1, label)
			if i == a.ask_sel {
				ui.buffer_text_clip(buf, x + 2, row_y, x + w - 2, fmt.tprintf("> %s", line), t.accent, t.bg)
			} else {
				ui.buffer_text_clip(buf, x + 2, row_y, x + w - 2, fmt.tprintf("  %s", line), t.fg, t.bg)
			}
			row_y += 1
		}
		hint := "Up/Down move · Enter select · 1-9 jump · Esc cancel"
		ui.buffer_text_clip(buf, x + 2, y + h - 2, x + w - 2, hint, t.muted, t.bg)
		return
	}

	shown := a.ask_buf
	masked := ""
	if a.ask_kind == .Secret {
		n := utf8.rune_count_in_string(a.ask_buf)
		masked, _ = strings.repeat("*", min(n, max(0, w - 4)), context.temp_allocator)
		shown = masked
	}
	caret := fmt.tprintf("%s_", shown)
	ui.buffer_text_clip(buf, x + 2, row_y + 1, x + w - 2, caret, t.accent, t.bg)
	hint := "Enter submit · Esc cancel"
	if a.ask_kind == .Confirm {
		hint = "y yes · n no · Esc cancel"
	} else if a.ask_kind == .Choice {
		hint = "Enter submit · Esc back to options"
	}
	ui.buffer_text_clip(buf, x + 2, y + h - 2, x + w - 2, hint, t.muted, t.bg)
}
