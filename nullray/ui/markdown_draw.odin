// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package ui

import "core:unicode/utf8"

// Per-kind paint for one inline markdown run. code_fg is passed in so
// callers can override the inline code color.
md_kind_paint :: proc(
	kind: Md_Inline_Kind,
	fg, code_fg, bg: Color,
	style: Style,
) -> (ofg, obg: Color, ostyle: Style) {
	t := theme()
	switch kind {
	case .Bold:
		return t.bold_fg, bg, style + {.Bold}
	case .Italic:
		return fg, bg, style + {.Italic}
	case .Strike:
		return fg, bg, style + {.Strikethrough}
	case .Code:
		return code_fg, t.code_bg, style
	case .Link:
		return t.link_fg, bg, style + {.Underline}
	case .Link_Url:
		return t.muted, bg, style + {.Dim}
	case .Normal:
		return fg, bg, style
	}
	return fg, bg, style
}

// Draw one visual line of pre-flattened markdown text. kinds holds one
// kind per byte of text. Returns columns written.
draw_flat_md_line :: proc(
	b: ^Buffer,
	x, y, width: int,
	text: string,
	kinds: []Md_Inline_Kind,
	fg, code_fg, bg: Color,
	style: Style = {},
) -> int {
	if width <= 0 {
		return 0
	}
	cx := 0
	i := 0
	for i < len(text) {
		// Inline #rgb / #rrggbb gets a color chip after the token.
		if text[i] == '#' && i + 3 < len(text) {
			hex_len := 0
			if i + 7 <= len(text) && color_is_hex6(text[i+1:i+7]) {
				hex_len = 6
			} else if i + 4 <= len(text) && color_is_hex3(text[i+1:i+4]) {
				hex_len = 3
			}
			if hex_len > 0 {
				next := i + 1 + hex_len
				if next >= len(text) || !color_is_hex_char(text[next]) {
					tok := text[i:next]
					kind := Md_Inline_Kind.Normal
					if i < len(kinds) {
						kind = kinds[i]
					}
					ofg, obg, ostyle := md_kind_paint(kind, fg, code_fg, bg, style)
					for j := 0; j < len(tok); j += 1 {
						if cx + 1 > width {
							return cx
						}
						buffer_put(b, x + cx, y, rune(tok[j]), ofg, obg, ostyle)
						cx += 1
					}
					if c, ok := color_parse(tok); ok && cx + 3 <= width {
						cx += 1
						buffer_color_swatch(b, x + cx, y, c)
						cx += 2
					}
					i = next
					continue
				}
			}
		}
		r, size := utf8.decode_rune_in_string(text[i:])
		if size <= 0 {
			break
		}
		w := max(1, rune_cols(r))
		if cx + w > width {
			break
		}
		kind := Md_Inline_Kind.Normal
		if i < len(kinds) {
			kind = kinds[i]
		}
		ofg, obg, ostyle := md_kind_paint(kind, fg, code_fg, bg, style)
		buffer_put(b, x + cx, y, r, ofg, obg, ostyle)
		for k in 1 ..< w {
			buffer_put(b, x + cx + k, y, CELL_WIDE_CONT, ofg, obg, ostyle)
		}
		cx += w
		i += size
	}
	return cx
}

// Draw one visual line of markdown-ish text with inline styling.
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
	flat := md_inline_flatten(text, context.temp_allocator)
	return draw_flat_md_line(b, x, y, width, flat.text, flat.kinds, fg, code_fg, bg, style)
}

// Word-wrap and draw markdown text with inline styles. Returns lines used.
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
	flat := md_inline_flatten(text, context.temp_allocator)
	disp := flat.text
	drawn := 0
	vis := 0
	col := 0
	line_start := 0
	i := 0
	guard := 0
	max_guard := len(disp) * 2 + 8

	for i <= len(disp) {
		guard += 1
		if guard > max_guard {
			break
		}
		at_end := i >= len(disp)
		r: rune = 0
		size := 0
		if !at_end {
			r, size = utf8.decode_rune_in_string(disp[i:])
			if size <= 0 {
				break
			}
		}

		need_flush := at_end || r == '\n'
		rw := 0
		if !at_end && r != '\n' {
			rw = max(1, rune_cols(r))
			if col + rw > width && col > 0 {
				need_flush = true
			}
		}

		if need_flush {
			if vis >= skip_lines && drawn < max_lines {
				_ = draw_flat_md_line(
					b,
					x,
					y + drawn,
					width,
					disp[line_start:i],
					flat.kinds[line_start:i],
					fg,
					code_fg,
					bg,
					style,
				)
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

		col += rw
		i += size
	}
	return drawn
}

md_text_line_count :: proc(text: string, width: int) -> int {
	plain := md_inline_plain(text, context.temp_allocator)
	return wrap_line_count(plain, width)
}
