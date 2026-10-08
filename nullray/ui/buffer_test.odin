// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
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

@(test)
test_color_from_hsv_primaries :: proc(t: ^testing.T) {
	red := color_from_hsv(0, 1, 1)
	testing.expect_value(t, red.r, 255)
	testing.expect_value(t, red.g, 0)
	testing.expect_value(t, red.b, 0)

	green := color_from_hsv(120, 1, 1)
	testing.expect_value(t, green.r, 0)
	testing.expect_value(t, green.g, 255)
	testing.expect_value(t, green.b, 0)

	blue := color_from_hsv(240, 1, 1)
	testing.expect_value(t, blue.r, 0)
	testing.expect_value(t, blue.g, 0)
	testing.expect_value(t, blue.b, 255)

	gray := color_from_hsv(90, 0, 0.5)
	testing.expect(t, gray.r == gray.g && gray.g == gray.b)
}

@(test)
test_brand_letter_color_varies :: proc(t: ^testing.T) {
	a := brand_letter_color(0, 7, 0.1)
	b := brand_letter_color(3, 7, 0.1)
	c := brand_letter_color(6, 7, 0.1)
	// Neighbor letters differ so the title reads as a gradient.
	testing.expect(t, a != b || b != c)
	// Same letter and phase is stable.
	testing.expect_value(t, brand_letter_color(2, 7, 0.25), brand_letter_color(2, 7, 0.25))
}

@(test)
test_draw_brand_text_paints_letters :: proc(t: ^testing.T) {
	theme_set(INK)
	b := buffer_create(16, 2)
	defer buffer_destroy(&b)

	used := draw_brand_text(&b, 1, 0, "nullray", INK.status_bg, {.Bold}, INK.title)
	testing.expect_value(t, used, 7)
	testing.expect_value(t, buffer_at(&b, 1, 0).ch, 'n')
	testing.expect_value(t, buffer_at(&b, 7, 0).ch, 'y')
	// Letters are a static gradient, not a flat single color.
	c0 := buffer_at(&b, 1, 0).fg
	c3 := buffer_at(&b, 4, 0).fg
	testing.expect(t, c0 != c3)
	// Second paint matches the first (no time-based animation).
	b2 := buffer_create(16, 2)
	defer buffer_destroy(&b2)
	_ = draw_brand_text(&b2, 1, 0, "nullray", INK.status_bg, {.Bold}, INK.title)
	testing.expect_value(t, buffer_at(&b2, 1, 0).fg, c0)
	testing.expect_value(t, buffer_at(&b2, 4, 0).fg, c3)
}

@(test)
test_draw_brand_text_clips_to_width :: proc(t: ^testing.T) {
	theme_set(INK)
	b := buffer_create(4, 1)
	defer buffer_destroy(&b)
	used := draw_brand_text(&b, 0, 0, "nullray", INK.status_bg, {}, INK.title)
	testing.expect(t, used <= 4)
	testing.expect_value(t, buffer_at(&b, 0, 0).ch, 'n')
}

@(test)
test_color_lerp_endpoints :: proc(t: ^testing.T) {
	a := Color{0, 0, 0}
	b := Color{255, 128, 0}
	testing.expect_value(t, color_lerp(a, b, 0), a)
	testing.expect_value(t, color_lerp(a, b, 1), b)
	mid := color_lerp(a, b, 0.5)
	testing.expect(t, mid.r > 0 && mid.r < 255)
}

@(test)
test_anim_phase_bounds :: proc(t: ^testing.T) {
	p := anim_phase(1000)
	testing.expect(t, p >= 0 && p < 1)
	testing.expect_value(t, anim_phase(0), f32(0))
}
