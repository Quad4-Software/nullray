// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Display column width for terminal cells.
*/

package ui

import "core:strings"
import "core:unicode"
import "core:unicode/utf8"

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

/*
Truncate s to at most max_cols display columns, keeping rune boundaries.
When the text does not fit, the tail is replaced with an ellipsis so the
result still fits max_cols. Returns s itself when it already fits.
*/
ellipsize_cols :: proc(s: string, max_cols: int, allocator := context.temp_allocator) -> string {
	if max_cols <= 0 {
		return ""
	}
	if string_cols(s) <= max_cols {
		return s
	}
	limit := max_cols - 1
	col := 0
	cut := 0
	i := 0
	for i < len(s) {
		r, size := utf8.decode_rune_in_string(s[i:])
		if size <= 0 {
			break
		}
		w := max(1, rune_cols(r))
		if col + w > limit {
			break
		}
		col += w
		i += size
		cut = i
	}
	b: strings.Builder
	strings.builder_init(&b, allocator)
	strings.write_string(&b, s[:cut])
	strings.write_rune(&b, '…')
	return strings.to_string(b)
}
