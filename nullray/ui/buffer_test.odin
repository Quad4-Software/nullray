// SPDX-License-Identifier: 0BSD
package ui

import "core:testing"

@(test)
test_buffer_put_and_bounds :: proc(t: ^testing.T) {
	theme_set(INK)
	b := buffer_create(10, 4)
	defer buffer_destroy(&b)

	buffer_put(&b, 0, 0, 'A', INK.fg, INK.bg)
	cell := buffer_at(&b, 0, 0)
	testing.expect(t, cell != nil)
	testing.expect_value(t, cell.ch, 'A')

	buffer_put(&b, -1, 0, 'X', INK.fg, INK.bg)
	buffer_put(&b, 99, 99, 'X', INK.fg, INK.bg)
	testing.expect(t, buffer_at(&b, -1, 0) == nil)
	testing.expect(t, buffer_at(&b, 99, 99) == nil)
}

@(test)
test_buffer_text_clip :: proc(t: ^testing.T) {
	theme_set(INK)
	b := buffer_create(8, 2)
	defer buffer_destroy(&b)

	buffer_text_clip(&b, 0, 0, 4, "HELLO", INK.fg, INK.bg)
	testing.expect_value(t, buffer_at(&b, 0, 0).ch, 'H')
	testing.expect_value(t, buffer_at(&b, 3, 0).ch, 'L')
	testing.expect_value(t, buffer_at(&b, 4, 0).ch, ' ')
}

@(test)
test_draw_status_bar_layout :: proc(t: ^testing.T) {
	theme_set(INK)
	b := buffer_create(40, 3)
	defer buffer_destroy(&b)

	draw_status_bar(&b, 1, "left-status", "RIGHT", INK.status_fg, INK.status_bg)
	testing.expect_value(t, buffer_at(&b, 1, 1).ch, 'l')
	right_start := b.width - string_cols("RIGHT") - 1
	testing.expect_value(t, buffer_at(&b, right_start, 1).ch, 'R')
}

@(test)
test_draw_wrapped_text_lines :: proc(t: ^testing.T) {
	theme_set(INK)
	b := buffer_create(20, 6)
	defer buffer_destroy(&b)

	used := draw_wrapped_text(&b, 0, 0, 5, 4, "abcdefghij", INK.fg, INK.bg)
	testing.expect(t, used >= 2)
	testing.expect_value(t, buffer_at(&b, 0, 0).ch, 'a')
	testing.expect_value(t, buffer_at(&b, 0, 1).ch, 'f')
}

@(test)
test_draw_wrapped_text_tail :: proc(t: ^testing.T) {
	theme_set(INK)
	b := buffer_create(20, 6)
	defer buffer_destroy(&b)

	testing.expect_value(t, wrap_line_count("abcdefghij", 5), 2)
	used, end_col := draw_wrapped_text_tail(&b, 0, 0, 5, 1, "abcdefghij", INK.fg, INK.bg)
	testing.expect_value(t, used, 1)
	testing.expect_value(t, buffer_at(&b, 0, 0).ch, 'f')
	testing.expect_value(t, end_col, 5)
}

@(test)
test_sanitize_control_runes :: proc(t: ^testing.T) {
	theme_set(INK)
	b := buffer_create(4, 1)
	defer buffer_destroy(&b)
	buffer_put(&b, 0, 0, '\n', INK.fg, INK.bg)
	testing.expect_value(t, buffer_at(&b, 0, 0).ch, ' ')
}

@(test)
test_string_cols_ascii :: proc(t: ^testing.T) {
	testing.expect_value(t, string_cols("nullray"), 7)
	testing.expect_value(t, string_cols(""), 0)
}
