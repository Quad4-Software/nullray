// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Fenced code blocks in the transcript. Lines get syntax spans from
ui.highlight_line when the fence tag names a known language.
*/

package app

import "core:fmt"
import "nullray:ui"

@(private)
app_draw_code_block :: proc(
	buf: ^ui.Buffer,
	block: Transcript_Block,
	y, remain, local_skip: int,
	area_x: int,
	area_w: int,
) -> int {
	t := ui.theme()
	if remain <= 0 {
		return 0
	}
	content_w := area_w
	if content_w <= 0 {
		content_w = buf.width
	}
	x0 := area_x + 1
	inner_w := max(1, content_w - 4)
	total := max(1, len(ui.word_wrap_lines(block.body, inner_w, context.temp_allocator)))
	lines := ui.word_wrap_lines(block.body, inner_w, context.temp_allocator, CODE_PREVIEW_LINES)
	shown_body := min(total, CODE_PREVIEW_LINES)
	code_bg := t.code_bg
	hl := ui.hl_known_lang(block.lang)
	used := 0
	vis := 0
	x_end := area_x + content_w - 1

	if local_skip == 0 && used < remain {
		ui.buffer_fill_rect(buf, x0, y, max(1, x_end - x0), 1, ' ', t.muted, code_bg)
		hdr := fmt.tprintf("┌ %s ", block.lang)
		ui.buffer_text_clip(buf, x0 + 1, y, x_end, hdr, t.accent, code_bg, {.Bold})
		rule_x := x0 + 1 + ui.string_cols(hdr)
		if rule_x < x_end {
			for cx := rule_x; cx < x_end; cx += 1 {
				ui.buffer_put(buf, cx, y, '─', t.border, code_bg)
			}
		}
		used += 1
	}
	vis += 1

	start_line := 0
	if local_skip > 1 {
		start_line = local_skip - 1
	}
	for li in start_line ..< shown_body {
		if used >= remain {
			break
		}
		if local_skip > 0 && vis < local_skip {
			vis += 1
			continue
		}
		line := ""
		if li < len(lines) {
			line = lines[li]
		}
		row := y + used
		ui.buffer_fill_rect(buf, x0, row, max(1, x_end - x0), 1, ' ', t.fg, code_bg)
		ui.buffer_text(buf, x0 + 1, row, "│ ", t.border, code_bg)
		cx := x0 + 3
		spans: []ui.Hl_Span
		if hl {
			spans = ui.highlight_line(block.lang, line, context.temp_allocator)
		}
		if len(spans) == 0 {
			ui.buffer_text_clip(buf, cx, row, x_end, line, t.code_fg, code_bg)
		} else {
			for sp in spans {
				if sp.start >= len(line) || sp.end <= sp.start {
					continue
				}
				end := min(sp.end, len(line))
				chunk := line[sp.start:end]
				c := ui.hl_color(sp.kind, t)
				if sp.kind == .Normal {
					c = t.code_fg
				}
				ui.buffer_text_clip(buf, cx, row, x_end, chunk, c, code_bg)
				cx += ui.string_cols(chunk)
				if cx >= x_end {
					break
				}
			}
		}
		used += 1
		vis += 1
	}

	footer_vis := 1 + shown_body
	if used < remain && !(local_skip > 0 && vis < local_skip) {
		row := y + used
		ui.buffer_fill_rect(buf, x0, row, max(1, x_end - x0), 1, ' ', t.muted, code_bg)
		foot := "└"
		if total > CODE_PREVIEW_LINES {
			foot = fmt.tprintf("└ … %d more", total - CODE_PREVIEW_LINES)
		}
		ui.buffer_text_clip(buf, x0 + 1, row, x_end, foot, t.muted, code_bg, {.Dim})
		rule_x := x0 + 1 + ui.string_cols(foot) + 1
		if total <= CODE_PREVIEW_LINES && rule_x < x_end {
			for cx := rule_x; cx < x_end; cx += 1 {
				ui.buffer_put(buf, cx, row, '─', t.border, code_bg)
			}
		}
		used += 1
		vis = footer_vis
	}
	return max(used, 0)
}
