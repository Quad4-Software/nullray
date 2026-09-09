// SPDX-License-Identifier: 0BSD
/*
Immediate-mode painters for common chrome.
*/

package ui

import "core:fmt"
import "core:unicode/utf8"

draw_box :: proc(b: ^Buffer, x, y, w, h: int, fg, bg: Color, title := "") {
	if w < 2 || h < 2 {
		return
	}
	buffer_put(b, x, y, '┌', fg, bg)
	buffer_put(b, x + w - 1, y, '┐', fg, bg)
	buffer_put(b, x, y + h - 1, '└', fg, bg)
	buffer_put(b, x + w - 1, y + h - 1, '┘', fg, bg)
	buffer_hline(b, x + 1, y, w - 2, '─', fg, bg)
	buffer_hline(b, x + 1, y + h - 1, w - 2, '─', fg, bg)
	buffer_vline(b, x, y + 1, h - 2, '│', fg, bg)
	buffer_vline(b, x + w - 1, y + 1, h - 2, '│', fg, bg)
	if len(title) > 0 {
		label := fmt.tprintf(" %s ", title)
		buffer_text_clip(b, x + 2, y, x + w - 2, label, fg, bg, {.Bold})
	}
}

draw_status_bar :: proc(b: ^Buffer, y: int, left, right: string, fg, bg: Color) {
	draw_status_bar_ex(b, y, left, right, fg, fg, bg)
}

draw_status_bar_ex :: proc(b: ^Buffer, y: int, left, right: string, left_fg, right_fg, bg: Color) {
	buffer_fill_rect(b, 0, y, b.width, 1, ' ', left_fg, bg)
	rw := string_cols(right)
	right_x := max(1, b.width - rw - 1)
	buffer_text_clip(b, 1, y, right_x - 1, left, left_fg, bg)
	buffer_text(b, right_x, y, right, right_fg, bg)
}

draw_input_line :: proc(b: ^Buffer, y: int, prompt, text: string, cursor: int, fg, bg, prompt_fg: Color) {
	buffer_fill_rect(b, 0, y, b.width, 1, ' ', fg, bg)
	buffer_text(b, 1, y, prompt, prompt_fg, bg, {.Bold})
	px := 1 + string_cols(prompt)
	safe_cursor := cursor_snap_boundary(text, clamp(cursor, 0, len(text)))
	buffer_text_clip(b, px, y, b.width - 1, text, fg, bg)
	cx := px + string_cols(text[:safe_cursor])
	if cx < b.width {
		cell := buffer_at(b, cx, y)
		if cell != nil {
			cell.style += {.Reverse}
		}
	}
}

wrap_line_count :: proc(text: string, width: int) -> int {
	if width <= 0 {
		return 0
	}
	if len(text) == 0 {
		return 1
	}
	col := 0
	lines := 1
	i := 0
	for i < len(text) {
		r, size := utf8.decode_rune_in_string(text[i:])
		if size <= 0 {
			break
		}
		if r == '\n' {
			lines += 1
			col = 0
			i += size
			continue
		}
		w := max(1, rune_cols(r))
		if col + w > width {
			lines += 1
			col = 0
		}
		col += w
		i += size
	}
	return lines
}

wrap_last_line_cols :: proc(text: string, width: int) -> int {
	if width <= 0 || len(text) == 0 {
		return 0
	}
	col := 0
	i := 0
	for i < len(text) {
		r, size := utf8.decode_rune_in_string(text[i:])
		if size <= 0 {
			break
		}
		if r == '\n' {
			col = 0
			i += size
			continue
		}
		w := max(1, rune_cols(r))
		if col + w > width {
			col = 0
		}
		col += w
		i += size
	}
	return col
}

draw_wrapped_text :: proc(b: ^Buffer, x, y, width, max_lines: int, text: string, fg, bg: Color, style: Style = {}) -> int {
	return draw_wrapped_text_skip(b, x, y, width, max_lines, text, 0, fg, bg, style)
}

draw_wrapped_text_skip :: proc(
	b: ^Buffer,
	x, y, width, max_lines: int,
	text: string,
	skip_lines: int,
	fg, bg: Color,
	style: Style = {},
) -> int {
	if width <= 0 || max_lines <= 0 {
		return 0
	}
	if len(text) == 0 {
		return 0
	}
	line := 0
	drawn := 0
	col := 0
	start := 0
	i := 0
	for i < len(text) {
		r, size := utf8.decode_rune_in_string(text[i:])
		if size <= 0 {
			break
		}
		if r == '\n' {
			if line >= skip_lines {
				buffer_text_clip(b, x, y + drawn, x + width, text[start:i], fg, bg, style)
				drawn += 1
				if drawn >= max_lines {
					return drawn
				}
			}
			line += 1
			i += size
			start = i
			col = 0
			continue
		}
		w := max(1, rune_cols(r))
		if col + w > width {
			if line >= skip_lines {
				buffer_text_clip(b, x, y + drawn, x + width, text[start:i], fg, bg, style)
				drawn += 1
				if drawn >= max_lines {
					return drawn
				}
			}
			line += 1
			start = i
			col = 0
		}
		col += w
		i += size
	}
	if start < len(text) && drawn < max_lines && line >= skip_lines {
		buffer_text_clip(b, x, y + drawn, x + width, text[start:], fg, bg, style)
		drawn += 1
	}
	return drawn
}

draw_wrapped_text_tail :: proc(
	b: ^Buffer,
	x, y, width, max_lines: int,
	text: string,
	fg, bg: Color,
	style: Style = {},
) -> (used: int, end_col: int) {
	if width <= 0 || max_lines <= 0 {
		return 0, 0
	}
	total := wrap_line_count(text, width)
	skip := max(0, total - max_lines)
	used = draw_wrapped_text_skip(b, x, y, width, max_lines, text, skip, fg, bg, style)
	if used <= 0 {
		return 0, 0
	}
	end_col = wrap_last_line_cols(text, width)
	return used, end_col
}

draw_stream_caret :: proc(b: ^Buffer, x, y, end_col: int, fg, bg: Color) {
	cx := x + end_col
	if cx < 0 || cx >= b.width || y < 0 || y >= b.height {
		return
	}
	on := anim_pulse(700) > 0.45
	if !on {
		return
	}
	cell := buffer_at(b, cx, y)
	if cell != nil {
		cell.style += {.Reverse}
		cell.fg = fg
		cell.bg = bg
	}
}
