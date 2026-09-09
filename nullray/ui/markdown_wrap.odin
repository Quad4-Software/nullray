// SPDX-License-Identifier: 0BSD
package ui

import "core:strings"
import "core:unicode"
import "core:unicode/utf8"

word_wrap_lines :: proc(text: string, width: int, allocator := context.temp_allocator, max_lines := 0) -> []string {
	if width <= 0 {
		if len(text) == 0 {
			return nil
		}
		lines: [dynamic]string
		lines.allocator = allocator
		append(&lines, strings.clone(text, allocator))
		return lines[:]
	}
	if len(text) == 0 {
		lines: [dynamic]string
		lines.allocator = allocator
		append(&lines, strings.clone("", allocator))
		return lines[:]
	}

	buf: [dynamic]u8
	buf.allocator = allocator
	lines: [dynamic]string
	lines.allocator = allocator

	line_start := 0
	col := 0
	last_break := -1
	i := 0
	stall := 0

	for i < len(text) {
		if max_lines > 0 && len(lines) >= max_lines {
			break
		}
		r, size := utf8.decode_rune_in_string(text[i:])
		if size <= 0 {
			break
		}

		if r == '\n' {
			word_wrap_push_line(&lines, buf[:], line_start, len(buf))
			line_start = len(buf)
			col = 0
			last_break = -1
			stall = 0
			i += size
			continue
		}

		rw := max(1, rune_cols(r))
		if col + rw > width && col > 0 {
			prev_line_start := line_start
			if last_break > line_start {
				word_wrap_push_line(&lines, buf[:], line_start, last_break)
				line_start = last_break
				for line_start < len(buf) && buf[line_start] == ' ' {
					line_start += 1
				}
			} else {
				word_wrap_push_line(&lines, buf[:], line_start, len(buf))
				line_start = len(buf)
			}
			col = word_wrap_cols(buf[line_start:])
			last_break = -1
			if line_start == prev_line_start {
				stall += 1
				if stall > 2 {
					// Force progress to avoid a hang on pathological widths.
					for j in 0 ..< size {
						append(&buf, text[i + j])
					}
					col += rw
					i += size
					stall = 0
				}
			} else {
				stall = 0
			}
			continue
		}

		for j in 0 ..< size {
			append(&buf, text[i + j])
		}

		if unicode.is_space(r) || word_wrap_is_break_rune(r) {
			last_break = len(buf)
		}

		col += rw
		i += size
		stall = 0
	}

	if max_lines <= 0 || len(lines) < max_lines {
		if line_start < len(buf) {
			word_wrap_push_line(&lines, buf[:], line_start, len(buf))
		} else if len(lines) == 0 {
			append(&lines, string(buf[:0]))
		}
	}

	return lines[:]
}

@(private)
word_wrap_push_line :: proc(lines: ^[dynamic]string, buf: []u8, start, end: int) {
	e := end
	for e > start && buf[e - 1] == ' ' {
		e -= 1
	}
	append(lines, string(buf[start:e]))
}

@(private)
word_wrap_cols :: proc(s: []u8) -> int {
	col := 0
	i := 0
	for i < len(s) {
		r, size := utf8.decode_rune_in_string(string(s[i:]))
		if size <= 0 {
			break
		}
		col += max(1, rune_cols(r))
		i += size
	}
	return col
}

@(private)
word_wrap_is_break_rune :: proc(r: rune) -> bool {
	switch r {
	case '.', ',', ';', ':', '!', '?', '-', '/', ')':
		return true
	}
	return false
}
