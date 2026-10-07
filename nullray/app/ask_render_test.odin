// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package app

import "core:strings"
import "core:testing"
import "nullray:session"
import "nullray:ui"

@(private)
row_text :: proc(buf: ^ui.Buffer, y: int, allocator := context.temp_allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	for x in 0 ..< buf.width {
		cell := ui.buffer_at(buf, x, y)
		if cell == nil {
			continue
		}
		ch := cell.ch
		if ch == ui.CELL_WIDE_CONT {
			continue
		}
		strings.write_rune(&b, ch)
	}
	return strings.to_string(b)
}

@(test)
test_ask_modal_wraps_prompt :: proc(t: ^testing.T) {
	ui.theme_set(ui.INK)
	s := new(session.Session)
	defer free(s)
	session.session_init(s)
	s.persist = false
	a := &App{session = s}
	a.ask_active = true
	a.ask_id = 7
	a.ask_kind = .Choice
	a.ask_prompt = "Which approach should the agent take for this very important and lengthy decision?"
	append(&a.ask_options, "first")
	append(&a.ask_options, "second")

	buf := ui.buffer_create(30, 14)
	defer ui.buffer_destroy(&buf)
	app_draw_ask_modal(&buf, a)

	// The question must wrap across rows inside the box, not clip off.
	found_which, found_decision := false, false
	for y in 0 ..< buf.height {
		row := row_text(&buf, y)
		if strings.contains(row, "Which approach") {
			found_which = true
		}
		if strings.contains(row, "decision?") {
			found_decision = true
		}
	}
	testing.expect(t, found_which)
	testing.expect(t, found_decision)
}

@(test)
test_ask_modal_no_bleed_through :: proc(t: ^testing.T) {
	ui.theme_set(ui.INK)
	s := new(session.Session)
	defer free(s)
	session.session_init(s)
	s.persist = false
	a := &App{session = s}
	a.ask_active = true
	a.ask_id = 7
	a.ask_kind = .Confirm
	a.ask_prompt = "ok?"

	buf := ui.buffer_create(40, 14)
	defer ui.buffer_destroy(&buf)
	// Ink the buffer first so a transparent modal would show through.
	for x in 0 ..< buf.width {
		for y in 0 ..< buf.height {
			ui.buffer_put(&buf, x, y, 'X', ui.INK.fg, ui.INK.bg)
		}
	}
	app_draw_ask_modal(&buf, a)

	// Between the box borders no leftover X may survive: the interior
	// is painted opaque so the underlying screen cannot bleed through.
	for y in 0 ..< buf.height {
		left, right := -1, -1
		for x in 0 ..< buf.width {
			cell := ui.buffer_at(&buf, x, y)
			if cell == nil {
				continue
			}
			if cell.ch == '│' {
				if left < 0 {
					left = x
				}
				right = x
			}
		}
		if left < 0 {
			continue
		}
		for x in left + 1 ..< right {
			cell := ui.buffer_at(&buf, x, y)
			if cell == nil {
				continue
			}
			testing.expect(t, cell.ch != 'X')
		}
	}
}
