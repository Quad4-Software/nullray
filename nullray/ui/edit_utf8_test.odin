// SPDX-License-Identifier: 0BSD
package ui

import "core:testing"
import "core:unicode/utf8"

@(test)
test_rune_boundary_ascii :: proc(t: ^testing.T) {
	s := "hello"
	testing.expect(t, is_rune_boundary(s, 0))
	testing.expect(t, is_rune_boundary(s, 5))
	testing.expect(t, is_rune_boundary(s, 2))
}

@(test)
test_rune_boundary_utf8 :: proc(t: ^testing.T) {
	s := "a世b"
	testing.expect(t, is_rune_boundary(s, 0))
	testing.expect(t, is_rune_boundary(s, 1))
	testing.expect(t, !is_rune_boundary(s, 2))
	testing.expect(t, !is_rune_boundary(s, 3))
	testing.expect(t, is_rune_boundary(s, 4))
	testing.expect(t, is_rune_boundary(s, len(s)))
}

@(test)
test_cursor_prev_next_utf8 :: proc(t: ^testing.T) {
	s := "a世b"
	testing.expect_value(t, cursor_next_rune(s, 0), 1)
	testing.expect_value(t, cursor_next_rune(s, 1), 4)
	testing.expect_value(t, cursor_next_rune(s, 4), 5)
	testing.expect_value(t, cursor_prev_rune(s, 5), 4)
	testing.expect_value(t, cursor_prev_rune(s, 4), 1)
	testing.expect_value(t, cursor_prev_rune(s, 1), 0)
	testing.expect_value(t, cursor_snap_boundary(s, 2), 1)
	testing.expect_value(t, cursor_snap_boundary(s, 3), 1)
}

@(test)
test_cursor_prev_edit_combining :: proc(t: ^testing.T) {
	// e + combining acute (U+0301)
	s := "e\u0301x"
	end := len(s) - 1
	cut := cursor_prev_edit(s, end)
	testing.expect_value(t, cut, 0)
	testing.expect(t, is_rune_boundary(s, cut))
}

@(test)
test_truncate_utf8_bytes :: proc(t: ^testing.T) {
	s := "世a"
	testing.expect_value(t, truncate_utf8_bytes(s, 1), "")
	testing.expect_value(t, truncate_utf8_bytes(s, 3), "世")
	testing.expect_value(t, truncate_utf8_bytes(s, 4), "世a")
	testing.expect_value(t, truncate_utf8_bytes(s, 100), s)
}

@(test)
test_caret_column_wide :: proc(t: ^testing.T) {
	prompt := "> "
	text := "世"
	testing.expect_value(t, caret_column(prompt, text, 0), string_cols(prompt))
	testing.expect_value(t, caret_column(prompt, text, len(text)), string_cols(prompt) + string_cols(text))
	n := utf8.rune_count_in_string(text)
	testing.expect_value(t, n, 1)
}

@(test)
test_draw_input_line_caret_utf8 :: proc(t: ^testing.T) {
	theme_set(INK)
	b := buffer_create(20, 2)
	defer buffer_destroy(&b)
	text := "a世b"
	cursor := 4
	draw_input_line(&b, 0, "> ", text, cursor, INK.fg, INK.input_bg, INK.accent)
	cx := 1 + string_cols("> ") + string_cols(text[:cursor])
	cell := buffer_at(&b, cx, 0)
	testing.expect(t, cell != nil)
	testing.expect(t, .Reverse in cell.style)
}

@(test)
test_string_cols_wide_rune :: proc(t: ^testing.T) {
	testing.expect(t, string_cols("世") >= 2)
}
