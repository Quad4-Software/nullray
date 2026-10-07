// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package ui

import "core:strings"
import "core:testing"

@(test)
test_ellipsize_fits_passthrough :: proc(t: ^testing.T) {
	testing.expect_value(t, ellipsize_cols("hello", 10), "hello")
	testing.expect_value(t, ellipsize_cols("hello", 5), "hello")
}

@(test)
test_ellipsize_truncates_with_marker :: proc(t: ^testing.T) {
	out := ellipsize_cols("abcdefghij", 6)
	testing.expect_value(t, out, "abcde…")
	testing.expect(t, string_cols(out) <= 6)
}

@(test)
test_ellipsize_rune_boundary :: proc(t: ^testing.T) {
	// Wide runes count as two cells and must never be split.
	out := ellipsize_cols("ab界界cd", 5)
	testing.expect(t, strings.has_suffix(out, "…"))
	testing.expect(t, !strings.contains(out, "界界"))
	testing.expect(t, string_cols(out) <= 5)
}

@(test)
test_ellipsize_tiny_budget :: proc(t: ^testing.T) {
	testing.expect_value(t, ellipsize_cols("abcdef", 1), "…")
	testing.expect_value(t, ellipsize_cols("abcdef", 0), "")
}

@(test)
test_buffer_put_wide_rune_last_column :: proc(t: ^testing.T) {
	theme_set(INK)
	b := buffer_create(6, 2)
	defer buffer_destroy(&b)

	// A two-cell rune in the last column must not be stored: it would
	// wrap on a real terminal and bleed onto the next row.
	buffer_put(&b, 5, 0, '界', INK.fg, INK.bg)
	testing.expect_value(t, buffer_at(&b, 5, 0).ch, ' ')

	// Same rune one cell earlier still lands fine.
	buffer_put(&b, 4, 0, '界', INK.fg, INK.bg)
	testing.expect_value(t, buffer_at(&b, 4, 0).ch, '界')
}

@(test)
test_status_bar_right_overflow :: proc(t: ^testing.T) {
	theme_set(INK)
	b := buffer_create(20, 2)
	defer buffer_destroy(&b)

	right := "this right label is far too wide for the bar"
	draw_status_bar(&b, 1, "L", right, INK.status_fg, INK.status_bg)

	// Right label must be ellipsized to fit and end inside the row.
	cell := buffer_at(&b, b.width - 2, 1)
	testing.expect(t, cell != nil)
	testing.expect_value(t, cell.ch, '…')
	// Left label still has a home: the truncated right side starts at
	// or after column 1.
	cell_l := buffer_at(&b, 1, 1)
	testing.expect(t, cell_l != nil)
}

@(test)
test_draw_box_interior_is_opaque :: proc(t: ^testing.T) {
	theme_set(INK)
	b := buffer_create(12, 6)
	defer buffer_destroy(&b)

	// Seed the whole buffer with ink so any leftover content would show.
	for x in 0 ..< b.width {
		for y in 0 ..< b.height {
			buffer_put(&b, x, y, 'X', INK.fg, INK.bg)
		}
	}
	draw_box(&b, 2, 1, 8, 4, INK.accent, INK.bg, "t")

	// Cells strictly inside the box must be cleared to spaces.
	for x in 3 ..< 9 {
		for y in 2 ..< 4 {
			testing.expect_value(t, buffer_at(&b, x, y).ch, ' ')
		}
	}
	testing.expect_value(t, buffer_at(&b, 2, 1).ch, '┌')
	testing.expect_value(t, buffer_at(&b, 9, 4).ch, '┘')
}
