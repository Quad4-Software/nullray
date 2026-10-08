// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Shapes, plots, bars, and Bresenham lines on the art canvas.
*/

package art

import "core:math"
import "core:strings"
import "nullray:ui"

canvas_hline :: proc(c: ^Canvas, x, y, w: int, ch: rune = 0, fg: ui.Color = {}, has_fg := false) {
	ink := ch
	if ink == 0 {
		ink = c.unicode ? '─' : '-'
	}
	for i in 0 ..< w {
		canvas_put(c, x + i, y, ink, fg, has_fg)
	}
}

canvas_vline :: proc(c: ^Canvas, x, y, h: int, ch: rune = 0, fg: ui.Color = {}, has_fg := false) {
	ink := ch
	if ink == 0 {
		ink = c.unicode ? '│' : '|'
	}
	for i in 0 ..< h {
		canvas_put(c, x, y + i, ink, fg, has_fg)
	}
}

canvas_rect :: proc(c: ^Canvas, x, y, w, h: int, fill := false, fg: ui.Color = {}, has_fg := false) {
	if w <= 0 || h <= 0 {
		return
	}
	if fill {
		ink := canvas_ink(c)
		for dy in 0 ..< h {
			for dx in 0 ..< w {
				canvas_put(c, x + dx, y + dy, ink, fg, has_fg)
			}
		}
		return
	}
	tl := c.unicode ? '┌' : '+'
	tr := c.unicode ? '┐' : '+'
	bl := c.unicode ? '└' : '+'
	br := c.unicode ? '┘' : '+'
	hz := c.unicode ? '─' : '-'
	vt := c.unicode ? '│' : '|'
	canvas_put(c, x, y, tl, fg, has_fg)
	canvas_put(c, x + w - 1, y, tr, fg, has_fg)
	canvas_put(c, x, y + h - 1, bl, fg, has_fg)
	canvas_put(c, x + w - 1, y + h - 1, br, fg, has_fg)
	for i in 1 ..< w - 1 {
		canvas_put(c, x + i, y, hz, fg, has_fg)
		canvas_put(c, x + i, y + h - 1, hz, fg, has_fg)
	}
	for i in 1 ..< h - 1 {
		canvas_put(c, x, y + i, vt, fg, has_fg)
		canvas_put(c, x + w - 1, y + i, vt, fg, has_fg)
	}
}

canvas_line :: proc(c: ^Canvas, x0, y0, x1, y1: int, ch: rune = 0, fg: ui.Color = {}, has_fg := false) {
	ink := ch
	if ink == 0 {
		ink = canvas_ink(c)
	}
	dx := abs(x1 - x0)
	dy := -abs(y1 - y0)
	sx := x0 < x1 ? 1 : -1
	sy := y0 < y1 ? 1 : -1
	err := dx + dy
	x, y := x0, y0
	for {
		canvas_put(c, x, y, ink, fg, has_fg)
		if x == x1 && y == y1 {
			break
		}
		e2 := 2 * err
		if e2 >= dy {
			err += dy
			x += sx
		}
		if e2 <= dx {
			err += dx
			y += sy
		}
	}
}

canvas_circle :: proc(c: ^Canvas, cx, cy, r: int, fill := false, fg: ui.Color = {}, has_fg := false) {
	if r <= 0 {
		return
	}
	ink := canvas_ink(c)
	for y in -r ..= r {
		for x in -r ..= r {
			fx := f64(x) / 2.0
			fy := f64(y)
			d := math.sqrt(fx * fx + fy * fy)
			if fill {
				if d <= f64(r) + 0.35 {
					canvas_put(c, cx + x, cy + y, ink, fg, has_fg)
				}
			} else if d >= f64(r) - 0.55 && d <= f64(r) + 0.55 {
				canvas_put(c, cx + x, cy + y, ink, fg, has_fg)
			}
		}
	}
}

canvas_text :: proc(c: ^Canvas, x, y: int, s: string, fg: ui.Color = {}, has_fg := false) {
	cx := x
	for r in s {
		if r == '\n' {
			break
		}
		canvas_put(c, cx, y, r, fg, has_fg)
		cx += max(1, ui.rune_cols(r))
	}
}

canvas_bars :: proc(c: ^Canvas, x, y, height: int, values: []f64, fg: ui.Color = {}, has_fg := false) {
	if height <= 0 || len(values) == 0 {
		return
	}
	max_v := 0.0
	for v in values {
		if v > max_v {
			max_v = v
		}
	}
	if max_v <= 0 {
		max_v = 1
	}
	ink := canvas_ink(c)
	partials := []rune{' ', '▂', '▃', '▄', '▅', '▆', '▇', '█'}
	for i in 0 ..< len(values) {
		if x + i >= c.w {
			break
		}
		n := values[i] / max_v * f64(height)
		full := int(n)
		frac := n - f64(full)
		for h in 0 ..< height {
			py := y + height - 1 - h
			if h < full {
				canvas_put(c, x + i, py, c.unicode ? '█' : ink, fg, has_fg)
			} else if h == full && c.unicode {
				idx := clamp(int(frac * 7.0), 0, 7)
				if idx > 0 {
					canvas_put(c, x + i, py, partials[idx], fg, has_fg)
				}
			}
		}
	}
}

canvas_spark :: proc(c: ^Canvas, x, y: int, values: []f64, fg: ui.Color = {}, has_fg := false) {
	if len(values) == 0 {
		return
	}
	blocks := []rune{'_', '.', ':', '-', '=', '+', '#', '@'}
	ublocks := []rune{' ', '▁', '▂', '▃', '▄', '▅', '▆', '▇', '█'}
	min_v, max_v := values[0], values[0]
	for v in values {
		if v < min_v { min_v = v }
		if v > max_v { max_v = v }
	}
	span := max_v - min_v
	if span <= 0 {
		span = 1
	}
	for i in 0 ..< len(values) {
		t := (values[i] - min_v) / span
		if c.unicode {
			idx := clamp(int(t * 8.0), 0, 8)
			canvas_put(c, x + i, y, ublocks[idx], fg, has_fg)
		} else {
			idx := clamp(int(t * 7.0), 0, 7)
			canvas_put(c, x + i, y, blocks[idx], fg, has_fg)
		}
	}
}

canvas_plot_fn :: proc(c: ^Canvas, x, y, w, h: int, name: string, samples: int, fg: ui.Color = {}, has_fg := false) {
	if w < 3 || h < 3 {
		return
	}
	canvas_rect(c, x, y, w, h, false, fg, has_fg)
	n := samples
	if n < 2 {
		n = w - 2
	}
	if n > w - 2 {
		n = w - 2
	}
	pts := make([]struct{px, py: int}, n, context.temp_allocator)
	nm := strings.to_lower(strings.trim_space(name), context.temp_allocator)
	for i in 0 ..< n {
		t := f64(i) / f64(max(n - 1, 1))
		xv := t * 2.0 * math.PI
		yv: f64
		switch nm {
		case "sin", "sine":
			yv = math.sin(xv)
		case "cos", "cosine":
			yv = math.cos(xv)
		case "abs_sin", "absin":
			yv = math.abs(math.sin(xv))
		case "quad", "x2":
			u := t * 2 - 1
			yv = u * u
		case "noise", "rand":
			yv = math.sin(xv * 3.1 + f64(i) * 0.7) * 0.5 + math.sin(xv * 0.9)
		case:
			yv = math.sin(xv)
		}
		ny := (1.0 - (yv + 1.0) / 2.0) * f64(h - 3)
		pts[i] = {x + 1 + i * (w - 2) / max(n - 1, 1), y + 1 + clamp(int(ny), 0, h - 3)}
	}
	for i in 0 ..< n - 1 {
		canvas_line(c, pts[i].px, pts[i].py, pts[i + 1].px, pts[i + 1].py, 0, fg, has_fg)
	}
}

canvas_plot_xy :: proc(c: ^Canvas, x, y, w, h: int, xs, ys: []f64, fg: ui.Color = {}, has_fg := false) {
	if w < 3 || h < 3 || len(xs) == 0 || len(xs) != len(ys) {
		return
	}
	canvas_rect(c, x, y, w, h, false, fg, has_fg)
	min_x, max_x := xs[0], xs[0]
	min_y, max_y := ys[0], ys[0]
	for i in 0 ..< len(xs) {
		if xs[i] < min_x { min_x = xs[i] }
		if xs[i] > max_x { max_x = xs[i] }
		if ys[i] < min_y { min_y = ys[i] }
		if ys[i] > max_y { max_y = ys[i] }
	}
	sx := max_x - min_x
	sy := max_y - min_y
	if sx <= 0 { sx = 1 }
	if sy <= 0 { sy = 1 }
	ink := c.unicode ? '•' : '*'
	for i in 0 ..< len(xs) {
		px := x + 1 + int((xs[i] - min_x) / sx * f64(w - 3))
		py := y + 1 + int((1.0 - (ys[i] - min_y) / sy) * f64(h - 3))
		canvas_put(c, px, py, ink, fg, has_fg)
	}
}
