// SPDX-License-Identifier: 0BSD
/*
Side pane file viewer draw.
*/

package app

import "core:fmt"
import "core:path/filepath"
import "core:strings"
import "nullray:ui"

app_draw_view_pane :: proc(buf: ^ui.Buffer, a: ^App, lay: View_Layout) {
	if !lay.open || lay.pane_w <= 0 || lay.pane_h <= 0 {
		return
	}
	t := ui.theme()
	x0 := lay.pane_x
	w := lay.pane_w
	y0 := lay.pane_y
	h := lay.pane_h
	code_bg := t.code_bg

	ui.buffer_fill_rect(buf, x0, y0, w, h, ' ', t.fg, code_bg)

	if !lay.overlay && lay.split_x >= 0 {
		ui.buffer_vline(buf, lay.split_x, y0, h, '│', t.border, t.bg)
	}

	row := y0
	// Recent strip
	if len(a.view_recent) > 0 && row < y0 + h {
		ui.buffer_fill_rect(buf, x0, row, w, 1, ' ', t.muted, t.status_bg)
		cx := x0 + 1
		x_max := x0 + w - 1
		for i in 0 ..< len(a.view_recent) {
			if cx >= x_max {
				ui.buffer_text_clip(buf, max(x0 + 1, x_max - 1), row, x_max, "…", t.muted, t.status_bg)
				break
			}
			name := filepath.base(a.view_recent[i])
			label := name
			if i > 0 {
				sep := " · "
				if cx + ui.string_cols(sep) >= x_max {
					ui.buffer_text_clip(buf, max(x0 + 1, x_max - 1), row, x_max, "…", t.muted, t.status_bg)
					break
				}
				ui.buffer_text_clip(buf, cx, row, x_max, sep, t.muted, t.status_bg)
				cx += ui.string_cols(sep)
			}
			fg := t.muted
			style: ui.Style = {.Dim}
			if i == a.view_idx {
				fg = t.accent
				style = {.Bold}
			}
			if cx + ui.string_cols(label) > x_max {
				ui.buffer_text_clip(buf, cx, row, x_max, label, fg, t.status_bg, style)
				break
			}
			ui.buffer_text_clip(buf, cx, row, x_max, label, fg, t.status_bg, style)
			cx += ui.string_cols(label)
		}
		row += 1
	}

	// Header
	if row < y0 + h {
		base := filepath.base(a.view_path)
		lines_n := app_view_line_count(a.view_body)
		focus := ""
		if a.view_focus {
			focus = " · focus"
		}
		hdr := fmt.tprintf("%s · %d lines%s", base, lines_n, focus)
		ui.buffer_fill_rect(buf, x0, row, w, 1, ' ', t.title, t.highlight_bg)
		ui.buffer_text_clip(buf, x0 + 1, row, x0 + w - 1, hdr, t.title, t.highlight_bg, {.Bold})
		row += 1
	}

	body_top := row
	body_bot := y0 + h - 1
	if body_bot < body_top {
		return
	}
	body_h := body_bot - body_top
	if body_h <= 0 {
		return
	}

	// Footer hint on last row
	foot_y := body_bot
	ui.buffer_fill_rect(buf, x0, foot_y, w, 1, ' ', t.muted, t.status_bg)
	ui.buffer_text_clip(
		buf,
		x0 + 1,
		foot_y,
		x0 + w - 1,
		"Tab focus · [ ] files · Esc close",
		t.muted,
		t.status_bg,
		{.Dim},
	)
	body_h = foot_y - body_top
	if body_h <= 0 {
		return
	}

	all_lines := strings.split_lines(a.view_body, context.temp_allocator)
	total := len(all_lines)
	if total == 0 {
		total = 1
	}
	max_scroll := max(0, total - body_h)
	if a.view_scroll > max_scroll {
		a.view_scroll = max_scroll
	}
	lang := app_view_lang_from_path(a.view_path)
	gutter_w := 1
	{
		n := total
		gutter_w = 1
		for n > 0 {
			gutter_w += 1
			n /= 10
		}
		gutter_w = max(3, min(gutter_w, 5))
	}
	text_x := x0 + 1 + gutter_w + 1
	text_w := max(1, x0 + w - 1 - text_x)

	for i in 0 ..< body_h {
		li := a.view_scroll + i
		ry := body_top + i
		ui.buffer_fill_rect(buf, x0, ry, w, 1, ' ', t.fg, code_bg)
		if li >= total {
			continue
		}
		num := fmt.tprintf("%*d", gutter_w, li + 1)
		ui.buffer_text_clip(buf, x0 + 1, ry, text_x - 1, num, t.muted, code_bg, {.Dim})
		line := ""
		if li < len(all_lines) {
			line = all_lines[li]
		}
		spans := ui.highlight_line(lang, line, context.temp_allocator)
		cx := text_x
		if len(spans) == 0 {
			ui.buffer_text_clip(buf, cx, ry, x0 + w - 1, line, t.assistant_fg, code_bg)
		} else {
			for sp in spans {
				if sp.start >= len(line) || sp.end <= sp.start {
					continue
				}
				end := min(sp.end, len(line))
				chunk := line[sp.start:end]
				ui.buffer_text_clip(buf, cx, ry, x0 + w - 1, chunk, ui.hl_color(sp.kind, t), code_bg)
				cx += ui.string_cols(chunk)
				if cx >= x0 + w - 1 {
					break
				}
			}
			_ = text_w
		}
	}
}
