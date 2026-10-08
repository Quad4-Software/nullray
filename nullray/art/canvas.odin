// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Programmatic terminal art canvas. Agents describe ops (figlet, shapes,
plots). The engine rasterizes. LLMs never freehand box-draw.
*/

package art

import "core:fmt"
import "core:math"
import "core:strings"
import "nullray:ui"

ART_MAX_W :: 120
ART_MAX_H :: 60
ART_MIN_W :: 8
ART_MIN_H :: 4

Art_Cell :: struct {
	ch: rune,
	fg: ui.Color,
	has_fg: bool,
}

Canvas :: struct {
	w, h:   int,
	cells:  []Art_Cell,
	unicode: bool,
	ink:    rune, // fallback glyph when unicode off
}

canvas_create :: proc(w, h: int, unicode := true, ink: rune = '#', allocator := context.allocator) -> Canvas {
	cw := clamp(w, ART_MIN_W, ART_MAX_W)
	ch := clamp(h, ART_MIN_H, ART_MAX_H)
	n := cw * ch
	cells := make([]Art_Cell, n, allocator)
	for i in 0 ..< n {
		cells[i] = Art_Cell{ch = ' '}
	}
	ink_r := ink
	if ink_r == 0 {
		ink_r = '#'
	}
	return Canvas{w = cw, h = ch, cells = cells, unicode = unicode, ink = ink_r}
}

canvas_destroy :: proc(c: ^Canvas) {
	delete(c.cells)
	c^ = {}
}

canvas_at :: proc(c: ^Canvas, x, y: int) -> ^Art_Cell {
	if c == nil || x < 0 || y < 0 || x >= c.w || y >= c.h {
		return nil
	}
	return &c.cells[y * c.w + x]
}

canvas_put :: proc(c: ^Canvas, x, y: int, ch: rune, fg: ui.Color = {}, has_fg := false) {
	cell := canvas_at(c, x, y)
	if cell == nil {
		return
	}
	if ch == 0 {
		return
	}
	r := ch
	if !c.unicode && ch > 0x7f {
		r = c.ink
	}
	cell.ch = r
	if has_fg {
		cell.fg = fg
		cell.has_fg = true
	}
}

canvas_ink :: proc(c: ^Canvas) -> rune {
	if c.unicode {
		return '█'
	}
	return c.ink
}

canvas_clear :: proc(c: ^Canvas, ch: rune = ' ') {
	for i in 0 ..< len(c.cells) {
		c.cells[i] = Art_Cell{ch = ch}
	}
}

// Plain multiline string (no ANSI). Good for side pane and copy.
canvas_to_string :: proc(c: ^Canvas, allocator := context.allocator) -> string {
	if c == nil || c.w <= 0 || c.h <= 0 {
		return strings.clone("", allocator)
	}
	b: strings.Builder
	strings.builder_init(&b, allocator)
	for y in 0 ..< c.h {
		for x in 0 ..< c.w {
			ch := c.cells[y * c.w + x].ch
			if ch == 0 {
				ch = ' '
			}
			strings.write_rune(&b, ch)
		}
		if y + 1 < c.h {
			strings.write_byte(&b, '\n')
		}
	}
	return strings.to_string(b)
}

// Truecolor SGR art for external terminals / file export.
canvas_to_ansi :: proc(c: ^Canvas, allocator := context.allocator) -> string {
	if c == nil {
		return strings.clone("", allocator)
	}
	b: strings.Builder
	strings.builder_init(&b, allocator)
	for y in 0 ..< c.h {
		for x in 0 ..< c.w {
			cell := c.cells[y * c.w + x]
			ch := cell.ch
			if ch == 0 {
				ch = ' '
			}
			if cell.has_fg {
				fmt.sbprintf(&b, "\x1b[38;2;%d;%d;%dm", cell.fg.r, cell.fg.g, cell.fg.b)
				strings.write_rune(&b, ch)
				strings.write_string(&b, "\x1b[0m")
			} else {
				strings.write_rune(&b, ch)
			}
		}
		if y + 1 < c.h {
			strings.write_byte(&b, '\n')
		}
	}
	return strings.to_string(b)
}
