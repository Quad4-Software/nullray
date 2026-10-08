// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Import a limited ANSI SGR stream onto the canvas (colors + printables).
Ignores cursor addressing and clear-screen so agents cannot hijack the TUI.
*/

package art

import "core:strconv"
import "core:strings"
import "core:unicode/utf8"
import "nullray:ui"

// Rasterize a subset of ANSI: SGR colors, printable chars, \n \r \t.
// Returns error string if input is empty after strip.
ansi_blit :: proc(c: ^Canvas, raw: string, x0 := 0, y0 := 0) -> string {
	if c == nil || len(raw) == 0 {
		return "empty ansi"
	}
	x, y := x0, y0
	fg := ui.Color{}
	has_fg := false
	i := 0
	for i < len(raw) {
		if raw[i] == 0x1b && i + 1 < len(raw) && raw[i+1] == '[' {
			// CSI ... letter
			j := i + 2
			for j < len(raw) {
				ch := raw[j]
				if ch >= 0x40 && ch <= 0x7e {
					break
				}
				j += 1
			}
			if j >= len(raw) {
				break
			}
			final := raw[j]
			params := raw[i+2:j]
			if final == 'm' {
				fg, has_fg = ansi_apply_sgr(params, fg, has_fg)
			}
			// ignore all other CSI (H, J, K, A, B, ...)
			i = j + 1
			continue
		}
		r, sz := utf8.decode_rune_in_string(raw[i:])
		if sz <= 0 {
			break
		}
		i += sz
		if r == '\n' {
			y += 1
			x = x0
			continue
		}
		if r == '\r' {
			x = x0
			continue
		}
		if r == '\t' {
			x = x0 + ((x - x0) / 4 + 1) * 4
			continue
		}
		if r < 0x20 {
			continue
		}
		canvas_put(c, x, y, r, fg, has_fg)
		x += max(1, ui.rune_cols(r))
	}
	return ""
}

@(private)
ansi_apply_sgr :: proc(params: string, cur: ui.Color, cur_has: bool) -> (ui.Color, bool) {
	if len(strings.trim_space(params)) == 0 || params == "0" {
		return {}, false
	}
	parts := strings.split(params, ";", context.temp_allocator)
	fg := cur
	has := cur_has
	i := 0
	for i < len(parts) {
		n, ok := strconv.parse_int(strings.trim_space(parts[i]), 10)
		if !ok {
			i += 1
			continue
		}
		switch n {
		case 0:
			fg = {}
			has = false
		case 30 ..= 37:
			fg = ansi_basic(n - 30)
			has = true
		case 90 ..= 97:
			fg = ansi_bright(n - 90)
			has = true
		case 38:
			// 38;5;n or 38;2;r;g;b
			if i + 1 < len(parts) {
				mode, _ := strconv.parse_int(strings.trim_space(parts[i+1]), 10)
				if mode == 5 && i + 2 < len(parts) {
					idx, _ := strconv.parse_int(strings.trim_space(parts[i+2]), 10)
					fg = ansi_256(idx)
					has = true
					i += 2
				} else if mode == 2 && i + 4 < len(parts) {
					r, _ := strconv.parse_int(strings.trim_space(parts[i+2]), 10)
					g, _ := strconv.parse_int(strings.trim_space(parts[i+3]), 10)
					b, _ := strconv.parse_int(strings.trim_space(parts[i+4]), 10)
					fg = ui.Color{u8(clamp(r, 0, 255)), u8(clamp(g, 0, 255)), u8(clamp(b, 0, 255))}
					has = true
					i += 4
				}
			}
		}
		i += 1
	}
	return fg, has
}

@(private)
ansi_basic :: proc(i: int) -> ui.Color {
	table := [8]ui.Color{
		{0, 0, 0},
		{170, 0, 0},
		{0, 170, 0},
		{170, 85, 0},
		{0, 0, 170},
		{170, 0, 170},
		{0, 170, 170},
		{170, 170, 170},
	}
	if i < 0 || i > 7 {
		return table[7]
	}
	return table[i]
}

@(private)
ansi_bright :: proc(i: int) -> ui.Color {
	table := [8]ui.Color{
		{85, 85, 85},
		{255, 85, 85},
		{85, 255, 85},
		{255, 255, 85},
		{85, 85, 255},
		{255, 85, 255},
		{85, 255, 255},
		{255, 255, 255},
	}
	if i < 0 || i > 7 {
		return table[7]
	}
	return table[i]
}

@(private)
ansi_256 :: proc(idx: int) -> ui.Color {
	n := clamp(idx, 0, 255)
	if n < 16 {
		if n < 8 {
			return ansi_basic(n)
		}
		return ansi_bright(n - 8)
	}
	if n < 232 {
		// 6x6x6 cube
		v := n - 16
		r := v / 36
		g := (v % 36) / 6
		b := v % 6
		levels := [6]u8{0, 95, 135, 175, 215, 255}
		return ui.Color{levels[r], levels[g], levels[b]}
	}
	// grayscale
	g := u8(8 + (n - 232) * 10)
	return ui.Color{g, g, g}
}
