// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Retained cell buffer the UI paints into each frame.
*/

package ui

import "core:unicode/utf8"

Style :: bit_set[Style_Bit]
Style_Bit :: enum {
	Bold,
	Dim,
	Underline,
	Reverse,
	Italic,
	Strikethrough,
}

Cell :: struct {
	ch:    rune,
	fg:    Color,
	bg:    Color,
	style: Style,
}

Buffer :: struct {
	width:  int,
	height: int,
	cells:  []Cell,
}

buffer_create :: proc(width, height: int, allocator := context.allocator) -> Buffer {
	w := max(width, 1)
	h := max(height, 1)
	cells := make([]Cell, w * h, allocator)
	t := theme()
	for &c in cells {
		c = Cell{ch = ' ', fg = t.fg, bg = t.bg, style = {}}
	}
	return Buffer{width = w, height = h, cells = cells}
}

buffer_destroy :: proc(b: ^Buffer) {
	delete(b.cells)
	b^ = {}
}

buffer_resize :: proc(b: ^Buffer, width, height: int, allocator := context.allocator) {
	if b.width == width && b.height == height {
		return
	}
	buffer_destroy(b)
	b^ = buffer_create(width, height, allocator)
}

buffer_clear :: proc(b: ^Buffer, bg: Color, fg: Color) {
	// Fill without per-cell struct literal churn when possible.
	if len(b.cells) == 0 {
		return
	}
	blank := Cell{ch = ' ', fg = fg, bg = bg, style = {}}
	for &c in b.cells {
		c = blank
	}
}

buffer_at :: proc(b: ^Buffer, x, y: int) -> ^Cell {
	if x < 0 || y < 0 || x >= b.width || y >= b.height {
		return nil
	}
	return &b.cells[y * b.width + x]
}

sanitize_cell_rune :: proc(ch: rune) -> rune {
	if ch == CELL_WIDE_CONT {
		return ch
	}
	if ch < 0x20 || ch == 0x7f || (ch >= 0x80 && ch <= 0x9f) {
		return ' '
	}
	return ch
}

buffer_put :: proc(b: ^Buffer, x, y: int, ch: rune, fg, bg: Color, style: Style = {}) {
	cell := buffer_at(b, x, y)
	if cell == nil {
		return
	}
	out := sanitize_cell_rune(ch)
	// A wide glyph in the last column wraps to the next row on real
	// terminals and bleeds over whatever is drawn there. Drop it.
	if x + rune_cols(out) > b.width {
		out = ' '
	}
	cell.ch = out
	cell.fg = fg
	cell.bg = bg
	cell.style = style
}

buffer_text :: proc(b: ^Buffer, x, y: int, text: string, fg, bg: Color, style: Style = {}) {
	cx := x
	for r in text {
		if r == '\n' {
			break
		}
		w := rune_cols(r)
		ch := r
		if w <= 0 {
			if r < 0x20 || r == 0x7f || (r >= 0x80 && r <= 0x9f) {
				ch = ' '
				w = 1
			} else {
				continue
			}
		}
		if cx + w > b.width {
			break
		}
		buffer_put(b, cx, y, ch, fg, bg, style)
		for i in 1 ..< w {
			buffer_put(b, cx + i, y, CELL_WIDE_CONT, fg, bg, style)
		}
		cx += w
	}
}

// Draw a solid color swatch (two cells) at (x,y). Used next to #rrggbb tokens.
buffer_color_swatch :: proc(b: ^Buffer, x, y: int, c: Color) {
	if b == nil {
		return
	}
	// Full block runes give a visible chip even on monochrome-ish fonts.
	buffer_put(b, x, y, '█', c, c, {})
	buffer_put(b, x + 1, y, '█', c, c, {})
}

/*
Paint text and render inline #rgb / #rrggbb tokens with a color chip after them.
Returns columns advanced (same semantics as a clipped paint).
*/
buffer_text_clip_colors :: proc(b: ^Buffer, x, y, x_max: int, text: string, fg, bg: Color, style: Style = {}) -> int {
	if b == nil || y < 0 || y >= b.height {
		return 0
	}
	cx := x
	i := 0
	for i < len(text) && cx < x_max {
		// Detect #rrggbb or #rgb starting at i
		if text[i] == '#' && i + 3 < len(text) {
			hex_len := 0
			if i + 7 <= len(text) && color_is_hex6(text[i+1:i+7]) {
				hex_len = 6
			} else if i + 4 <= len(text) && color_is_hex3(text[i+1:i+4]) {
				hex_len = 3
			}
			if hex_len > 0 {
				// boundary: next char not more hex
				next := i + 1 + hex_len
				if next >= len(text) || !color_is_hex_char(text[next]) {
					tok := text[i:next]
					c, ok := color_parse(tok)
					// paint the token itself
					for j := 0; j < len(tok) && cx < x_max; j += 1 {
						buffer_put(b, cx, y, rune(tok[j]), fg, bg, style)
						cx += 1
					}
					if ok && cx + 2 <= x_max {
						cx += 1 // gap
						if cx + 1 < x_max {
							buffer_color_swatch(b, cx, y, c)
							cx += 2
						}
					}
					i = next
					continue
				}
			}
		}
		r, sz := utf8.decode_rune_in_string(text[i:])
		if sz <= 0 {
			break
		}
		if r == CELL_WIDE_CONT {
			i += sz
			continue
		}
		w := max(1, rune_cols(r))
		if cx + w > x_max {
			break
		}
		buffer_put(b, cx, y, r, fg, bg, style)
		cx += w
		i += sz
	}
	return cx - x
}

@(private)
color_is_hex_char :: proc(c: u8) -> bool {
	return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
}

@(private)
color_is_hex3 :: proc(s: string) -> bool {
	if len(s) != 3 {
		return false
	}
	return color_is_hex_char(s[0]) && color_is_hex_char(s[1]) && color_is_hex_char(s[2])
}

@(private)
color_is_hex6 :: proc(s: string) -> bool {
	if len(s) != 6 {
		return false
	}
	for i in 0 ..< 6 {
		if !color_is_hex_char(s[i]) {
			return false
		}
	}
	return true
}

buffer_text_clip :: proc(b: ^Buffer, x, y, x_max: int, text: string, fg, bg: Color, style: Style = {}) {
	if x_max <= x {
		return
	}
	limit := min(b.width, x_max)
	cx := x
	for r in text {
		if r == '\n' {
			break
		}
		w := rune_cols(r)
		ch := r
		if w <= 0 {
			if r < 0x20 || r == 0x7f || (r >= 0x80 && r <= 0x9f) {
				ch = ' '
				w = 1
			} else {
				continue
			}
		}
		if cx + w > limit {
			break
		}
		buffer_put(b, cx, y, ch, fg, bg, style)
		for i in 1 ..< w {
			buffer_put(b, cx + i, y, CELL_WIDE_CONT, fg, bg, style)
		}
		cx += w
	}
}

buffer_fill_rect :: proc(b: ^Buffer, x, y, w, h: int, ch: rune, fg, bg: Color) {
	for row in 0 ..< h {
		for col in 0 ..< w {
			buffer_put(b, x + col, y + row, ch, fg, bg)
		}
	}
}

buffer_hline :: proc(b: ^Buffer, x, y, w: int, ch: rune, fg, bg: Color) {
	for i in 0 ..< w {
		buffer_put(b, x + i, y, ch, fg, bg)
	}
}

buffer_vline :: proc(b: ^Buffer, x, y, h: int, ch: rune, fg, bg: Color) {
	for i in 0 ..< h {
		buffer_put(b, x, y + i, ch, fg, bg)
	}
}
