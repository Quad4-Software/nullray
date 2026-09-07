// SPDX-License-Identifier: 0BSD
/*
Startup splash: colored Nullray wordmark reveal.

Glyph templates stay ASCII (# ink). When the terminal looks UTF-8 capable,
ink cells paint as U+2588 full block. Limited and legacy TERM keep #.
Auto-finishes on a timer. Any key or mouse dismisses it early.
*/

package app

import "core:os"
import "core:strings"
import "core:time"
import "nullray:constants"
import "nullray:ui"

SPLASH_MS :: 1400
SPLASH_GLYPH_MS :: 110

// Full block. Same cell width as # on capable terminals.
SPLASH_BLOCK :: rune(0x2588)

SPLASH_GLYPHS := [7][7]string{
	{
		"#   #",
		"##  #",
		"# # #",
		"#  ##",
		"#   #",
		"#   #",
		"#   #",
	},
	{
		"     ",
		"     ",
		"#   #",
		"#   #",
		"#   #",
		"#  ##",
		" ## #",
	},
	{
		"##   ",
		" #   ",
		" #   ",
		" #   ",
		" #   ",
		" #   ",
		"###  ",
	},
	{
		"##   ",
		" #   ",
		" #   ",
		" #   ",
		" #   ",
		" #   ",
		"###  ",
	},
	{
		"     ",
		"     ",
		"# ## ",
		"##  #",
		"#    ",
		"#    ",
		"#    ",
	},
	{
		"     ",
		"     ",
		" ### ",
		"    #",
		" ####",
		"#   #",
		" ####",
	},
	{
		"     ",
		"     ",
		"#   #",
		"#   #",
		" ####",
		"    #",
		" ### ",
	},
}

SPLASH_COLORS := [7]ui.Color{
	{90, 210, 255},
	{70, 160, 230},
	{130, 120, 255},
	{160, 90, 220},
	{255, 140, 70},
	{255, 190, 80},
	{255, 230, 140},
}

splash_enabled_from_env :: proc() -> bool {
	if v, ok := os.lookup_env(constants.ENV_SPLASH, context.temp_allocator); ok {
		switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
		case "0", "false", "off", "no", "disable", "disabled":
			return false
		case "1", "true", "on", "yes":
			return true
		}
	}
	return true
}

// Ink-edge gaps match scripts/gen_logo.py (ll pair tighter).
splash_letter_gap :: proc(i: int) -> int {
	if i == 2 {
		return 0
	}
	return 1
}

splash_active :: proc(a: ^App) -> bool {
	if !a.splash_on {
		return false
	}
	elapsed := time.tick_diff(a.splash_start, time.tick_now())
	if elapsed >= time.Duration(SPLASH_MS) * time.Millisecond {
		a.splash_on = false
		return false
	}
	return true
}

splash_visible_letters :: proc(a: ^App) -> int {
	elapsed_ms := int(time.tick_diff(a.splash_start, time.tick_now()) / time.Millisecond)
	n := 1 + elapsed_ms / SPLASH_GLYPH_MS
	if n < 1 {
		n = 1
	}
	if n > 7 {
		n = 7
	}
	return n
}

splash_word_width :: proc(letters: int) -> int {
	w := 0
	for i in 0 ..< letters {
		w += 5
		if i + 1 < letters {
			w += splash_letter_gap(i)
		}
	}
	return w
}

splash_ink_rune :: proc(template: rune) -> rune {
	if template == ' ' {
		return ' '
	}
	if ui.term_utf8_ok() {
		return SPLASH_BLOCK
	}
	return '#'
}

app_draw_splash :: proc(buf: ^ui.Buffer, a: ^App) {
	t := ui.theme()
	ui.buffer_clear(buf, t.bg, t.fg)

	letters := splash_visible_letters(a)
	word_w := splash_word_width(letters)
	word_h := 7
	start_x := max(0, (buf.width - word_w) / 2)
	start_y := max(0, (buf.height - word_h) / 2 - 2)

	x := start_x
	for i in 0 ..< letters {
		col := SPLASH_COLORS[i]
		pulse := ui.anim_pulse(900)
		fg := ui.color_lerp(col, t.fg, pulse * 0.15)
		for row in 0 ..< 7 {
			line := SPLASH_GLYPHS[i][row]
			for cx := 0; cx < len(line); cx += 1 {
				ch := splash_ink_rune(rune(line[cx]))
				if ch == ' ' {
					continue
				}
				ui.buffer_put(buf, x + cx, start_y + row, ch, fg, t.bg, {.Bold})
			}
		}
		x += 5
		if i + 1 < letters {
			x += splash_letter_gap(i)
		}
	}

	slogan := "Simple, Lightweight, Fast"
	sx := max(0, (buf.width - len(slogan)) / 2)
	sy := min(buf.height - 3, start_y + word_h + 2)
	ui.buffer_text(buf, sx, sy, slogan, t.muted, t.bg, {.Dim})

	ver := constants.VERSION
	vx := max(0, (buf.width - len(ver)) / 2)
	vy := min(buf.height - 2, sy + 1)
	ui.buffer_text(buf, vx, vy, ver, t.muted, t.bg, {.Dim})

	hint := "any key"
	hx := max(0, (buf.width - len(hint)) / 2)
	hy := min(buf.height - 1, vy + 2)
	ui.buffer_text(buf, hx, hy, hint, t.muted, t.bg, {.Dim})
}
