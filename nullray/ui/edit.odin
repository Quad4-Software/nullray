// SPDX-License-Identifier: 0BSD
/*
Rune-boundary cursor helpers for TUI input editing.
*/

package ui

import "core:unicode"
import "core:unicode/utf8"

is_rune_boundary :: proc(s: string, i: int) -> bool {
	if i < 0 || i > len(s) {
		return false
	}
	if i == 0 || i == len(s) {
		return true
	}
	b := s[i]
	return (b & 0xc0) != 0x80
}

cursor_snap_boundary :: proc(s: string, cursor: int) -> int {
	c := clamp(cursor, 0, len(s))
	for c > 0 && !is_rune_boundary(s, c) {
		c -= 1
	}
	return c
}

cursor_prev_rune :: proc(s: string, cursor: int) -> int {
	c := cursor_snap_boundary(s, cursor)
	if c <= 0 {
		return 0
	}
	_, sz := utf8.decode_last_rune_in_string(s[:c])
	if sz <= 0 {
		return max(0, c - 1)
	}
	return c - sz
}

cursor_next_rune :: proc(s: string, cursor: int) -> int {
	c := cursor_snap_boundary(s, cursor)
	if c >= len(s) {
		return len(s)
	}
	_, sz := utf8.decode_rune_in_string(s[c:])
	if sz <= 0 {
		return min(len(s), c + 1)
	}
	return c + sz
}

/*
Backspace cut point: drop trailing combining marks with their base.
*/
cursor_prev_edit :: proc(s: string, cursor: int) -> int {
	c := cursor_snap_boundary(s, cursor)
	if c <= 0 {
		return 0
	}
	for c > 0 {
		r, sz := utf8.decode_last_rune_in_string(s[:c])
		if sz <= 0 {
			return max(0, c - 1)
		}
		c -= sz
		if !(unicode.is_nonspacing_mark(r) || unicode.is_spacing_mark(r) || unicode.is_enclosing_mark(r) || unicode.is_combining(r)) {
			break
		}
	}
	return c
}

truncate_utf8_bytes :: proc(s: string, max_bytes: int) -> string {
	if max_bytes <= 0 {
		return ""
	}
	if len(s) <= max_bytes {
		return s
	}
	i := 0
	for i < len(s) {
		_, sz := utf8.decode_rune_in_string(s[i:])
		if sz <= 0 {
			break
		}
		if i + sz > max_bytes {
			break
		}
		i += sz
	}
	return s[:i]
}

caret_column :: proc(prompt, text: string, cursor: int) -> int {
	c := cursor_snap_boundary(text, cursor)
	return string_cols(prompt) + string_cols(text[:c])
}
