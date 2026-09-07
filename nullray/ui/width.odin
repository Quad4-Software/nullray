/*
Display column width for terminal cells.
*/

package ui

import "core:unicode"

// Trailing cell of a wide glyph. Present skips writing it.
CELL_WIDE_CONT :: rune(0x10FFFE)

rune_cols :: proc(r: rune) -> int {
	if r == CELL_WIDE_CONT {
		return 0
	}
	w := unicode.normalized_east_asian_width(r)
	if w < 0 {
		return 1
	}
	return w
}

string_cols :: proc(s: string) -> int {
	n := 0
	for r in s {
		n += rune_cols(r)
	}
	return n
}
