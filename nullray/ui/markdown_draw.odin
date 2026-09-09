// SPDX-License-Identifier: 0BSD
package ui

import "core:strings"
import "core:unicode/utf8"

// Strip paired backticks for plain measurement. Unmatched ticks are dropped.
md_strip_inline_ticks :: proc(src: string, allocator := context.temp_allocator) -> string {
	if len(src) == 0 {
		return ""
	}
	b: strings.Builder
	strings.builder_init(&b, allocator)
	in_code := false
	i := 0
	for i < len(src) {
		if src[i] == '`' {
			in_code = !in_code
			i += 1
			continue
		}
		strings.write_byte(&b, src[i])
		i += 1
	}
	return strings.to_string(b)
}

// Draw one visual line of markdown-ish text with `inline code` coloring.
// Returns columns written.
draw_inline_md_line :: proc(
	b: ^Buffer,
	x, y, width: int,
	text: string,
	fg, code_fg, bg: Color,
	style: Style = {},
) -> int {
	if width <= 0 {
		return 0
	}
	cx := 0
	in_code := false
	i := 0
	for i < len(text) {
		if text[i] == '`' {
			in_code = !in_code
			i += 1
			continue
		}
		r, size := utf8.decode_rune_in_string(text[i:])
		if size <= 0 {
			break
		}
		w := max(1, rune_cols(r))
		if cx + w > width {
			break
		}
		use_fg := fg
		use_style := style
		if in_code {
			use_fg = code_fg
			use_style += {.Bold}
		}
		buffer_put(b, x + cx, y, r, use_fg, bg, use_style)
		cx += w
		i += size
	}
	return cx
}

// Word-wrap and draw markdown text with inline ticks. Returns lines used.
draw_md_text_wrapped :: proc(
	b: ^Buffer,
	x, y, width, max_lines: int,
	text: string,
	fg, code_fg, bg: Color,
	style: Style = {},
	skip_lines: int = 0,
) -> int {
	if width <= 0 || max_lines <= 0 {
		return 0
	}
	drawn := 0
	vis := 0
	col := 0
	line_start := 0
	i := 0
	guard := 0
	max_guard := len(text) * 2 + 8

	for i <= len(text) {
		guard += 1
		if guard > max_guard {
			break
		}
		at_end := i >= len(text)
		r: rune = 0
		size := 0
		if !at_end {
			r, size = utf8.decode_rune_in_string(text[i:])
			if size <= 0 {
				break
			}
		}

		need_flush := at_end || r == '\n'
		rw := 0
		if !at_end && r != '\n' && r != '`' {
			rw = max(1, rune_cols(r))
			if col + rw > width && col > 0 {
				need_flush = true
			}
		}

		if need_flush {
			if vis >= skip_lines && drawn < max_lines {
				seg := text[line_start:i]
				_ = draw_inline_md_line(b, x, y + drawn, width, seg, fg, code_fg, bg, style)
				drawn += 1
			}
			vis += 1
			if at_end {
				break
			}
			if r == '\n' {
				i += size
				line_start = i
				col = 0
				continue
			}
			// Soft wrap: restart line at current rune
			line_start = i
			col = 0
			if drawn >= max_lines {
				break
			}
			continue
		}

		if r == '`' {
			i += size
			continue
		}
		col += rw
		i += size
	}
	return drawn
}

md_text_line_count :: proc(text: string, width: int) -> int {
	plain := md_strip_inline_ticks(text, context.temp_allocator)
	return wrap_line_count(plain, width)
}
