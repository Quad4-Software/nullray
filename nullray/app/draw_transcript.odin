// SPDX-License-Identifier: 0BSD
/*
Transcript block collection and drawing.
*/

package app

import "core:fmt"
import "core:strings"
import "nullray:agent"
import "nullray:session"
import "nullray:ui"

@(private)
app_collect_blocks :: proc(a: ^App, accent: ui.Color, allocator := context.temp_allocator) -> []Transcript_Block {
	t := ui.theme()
	blocks := make([dynamic]Transcript_Block, 0, len(a.session.messages) + 4, allocator)
	for m in a.session.messages {
		app_append_gap(&blocks)

		label := "you"
		fg := t.user_fg
		pfx_fg := t.user_fg
		row_bg := t.bg
		has_bg := false
		gutter := true
		render_md := false
		body_style: ui.Style

		if m.role == .Assistant {
			label = "nullray"
			fg = t.assistant_fg
			pfx_fg = accent
			render_md = true
		} else if m.role == .System {
			label = "sys"
			fg = t.muted
			pfx_fg = t.muted
			gutter = false
			body_style = {.Dim}
		} else if m.role == .Tool {
			label = "tool"
			if len(m.name) > 0 {
				label = fmt.tprintf("tool:%s", m.name)
			}
			fg = t.muted
			pfx_fg = t.accent_dim
			gutter = false
			body_style = {.Dim}
			if session.looks_like_tool_error(m.content) {
				fg = t.error
				pfx_fg = t.error
				body_style = {}
			}
		} else if m.role == .User && strings.has_prefix(m.content, agent.VERIFY_USER_PREFIX) {
			label = "verify"
			fg = t.warn
			pfx_fg = t.warn
			gutter = false
		}

		if m.role == .Assistant && len(m.reasoning) > 0 {
			append(&blocks, Transcript_Block{
				prefix = "think  ",
				body = m.reasoning,
				prefix_fg = t.muted,
				body_fg = t.muted,
				prefix_style = {.Dim},
				body_style = {.Dim},
			})
		}

		pfx := fmt.tprintf("%s  ", label)
		body := m.content
		expand_kind := ""
		expand_id := ""
		if m.role == .Tool {
			if stub, ok := tool_artifact_stub(m.content, context.temp_allocator); ok {
				body = stub
				expand_kind = "artifact"
				idx := strings.index(m.content, "artifact=")
				if idx >= 0 {
					rest := m.content[idx + len("artifact="):]
					end := 0
					for end < len(rest) {
						c := rest[end]
						if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-' || c == '_' {
							end += 1
							continue
						}
						break
					}
					expand_id = rest[:end]
				}
			}
		}
		if render_md {
			app_append_md_content(&blocks, pfx, body, pfx_fg, fg, false, row_bg, has_bg, gutter)
		} else {
			append(&blocks, Transcript_Block{
				prefix = pfx,
				body = body,
				prefix_fg = pfx_fg,
				body_fg = fg,
				prefix_style = {.Bold},
				body_style = body_style,
				row_bg = row_bg,
				has_bg = has_bg,
				gutter = gutter,
				is_md = true,
				expand_kind = expand_kind,
				expand_id = expand_id,
			})
		}
	}

	if a.session.has_thinking || a.session.has_streaming || a.session.busy || len(a.session.live_tool) > 0 {
		app_append_gap(&blocks)
	}

	if a.session.has_thinking {
		think_body := strings.to_string(a.session.thinking)
		think_body = app_reveal_prefix(think_body, a.reveal_think)
		append(&blocks, Transcript_Block{
			prefix = "think  ",
			body = think_body,
			prefix_fg = t.muted,
			body_fg = t.muted,
			prefix_style = {.Dim},
			body_style = {.Dim},
		})
	}
	if len(a.session.live_tool) > 0 {
		run_body := a.session.live_tool_detail
		if len(run_body) == 0 {
			run_body = fmt.tprintf("running %s", a.session.live_tool)
		}
		append(&blocks, Transcript_Block{
			prefix = "run  ",
			body = fmt.tprintf("%s %s", ui.spinner_frame(&a.spinner), run_body),
			prefix_fg = t.accent,
			body_fg = t.accent_dim,
			prefix_style = {.Bold},
			body_style = {},
			gutter = false,
		})
	}
	if a.session.has_streaming {
		stream_accent := ui.color_lerp(t.accent_dim, t.accent, ui.anim_pulse(1200))
		stream_body := strings.to_string(a.session.streaming)
		stream_body = app_reveal_prefix(stream_body, a.reveal_stream)
		app_append_md_content(
			&blocks,
			"nullray  ",
			stream_body,
			stream_accent,
			t.assistant_fg,
			true,
			{},
			false,
			true,
		)
	} else if a.session.busy && len(a.session.live_tool) == 0 && !a.session.has_thinking {
		append(&blocks, Transcript_Block{
			prefix = "nullray  ",
			body = fmt.tprintf("%s waiting…", ui.spinner_frame(&a.spinner)),
			prefix_fg = accent,
			body_fg = t.muted,
			prefix_style = {.Bold},
			body_style = {.Dim},
			gutter = true,
		})
	} else if a.session.busy && len(a.session.live_tool) == 0 {
		append(&blocks, Transcript_Block{
			prefix = "nullray  ",
			body = "…",
			prefix_fg = accent,
			body_fg = t.muted,
			prefix_style = {.Bold},
			gutter = true,
		})
	}
	return blocks[:]
}

@(private)
app_draw_blocks :: proc(
	a: ^App,
	buf: ^ui.Buffer,
	blocks: []Transcript_Block,
	heights: []int,
	msg_top, msg_h, skip_lines: int,
	caret_fg, caret_bg: ui.Color,
	area_x: int,
	area_w: int,
) {
	t := ui.theme()
	content_w := area_w
	if content_w <= 0 {
		content_w = buf.width
	}
	skip := skip_lines
	y := msg_top
	remain := msg_h
	for bi in 0 ..< len(blocks) {
		block := blocks[bi]
		if remain <= 0 {
			break
		}
		h := heights[bi]
		if skip >= h {
			skip -= h
			continue
		}
		local_skip := skip
		skip = 0

		if block.gap {
			if local_skip == 0 {
				y += 1
				remain -= 1
			}
			continue
		}

		if block.is_code {
			y_start := y
			used := app_draw_code_block(buf, block, y, remain, local_skip, area_x, content_w)
			if a != nil && len(block.expand_kind) > 0 && used > 0 {
				app_expand_hit_push(a, y_start, y_start + used - 1, block.expand_kind, block.expand_id, block.expand_body)
			}
			y += used
			remain -= used
			continue
		}

		bg := t.bg
		if block.has_bg {
			bg = block.row_bg
			fill_h := min(h - local_skip, remain)
			if fill_h > 0 {
				ui.buffer_fill_rect(buf, area_x, y, content_w, fill_h, ' ', block.body_fg, bg)
			}
		}

		bw := block_body_width(content_w, block.prefix)
		px := area_x + CONTENT_X + ui.string_cols(block.prefix)
		y_start := y

		if local_skip == 0 {
			if block.gutter {
				ui.buffer_put(buf, area_x, y, '▏', block.prefix_fg, bg)
			}
			if len(block.prefix) > 0 {
				ui.buffer_text(buf, area_x + CONTENT_X, y, block.prefix, block.prefix_fg, bg, block.prefix_style)
			}
		}

		body := block.body
		if len(body) == 0 {
			if local_skip == 0 {
				if a != nil && len(block.expand_kind) > 0 {
					app_expand_hit_push(a, y_start, y_start, block.expand_kind, block.expand_id, block.expand_body)
				}
				y += 1
				remain -= 1
			}
			continue
		}

		used := 0
		if block.is_md {
			used = ui.draw_md_text_wrapped(buf, px, y, bw, remain, body, block.body_fg, t.accent, bg, block.body_style, local_skip)
		} else {
			used = ui.draw_wrapped_text_skip(buf, px, y, bw, remain, body, local_skip, block.body_fg, bg, block.body_style)
		}
		if used <= 0 {
			used = 1
			if local_skip == 0 {
				ui.buffer_text(buf, px, y, body, block.body_fg, bg, block.body_style)
			}
		}
		if block.caret && local_skip + used >= h {
			end_col := ui.wrap_last_line_cols(ui.md_strip_inline_ticks(body), bw)
			ui.draw_stream_caret(buf, px, y + used - 1, end_col, caret_fg, caret_bg)
		}
		if a != nil && len(block.expand_kind) > 0 && used > 0 {
			app_expand_hit_push(a, y_start, y_start + used - 1, block.expand_kind, block.expand_id, block.expand_body)
		}
		y += used
		remain -= used
	}
}

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
	total := max(1, ui.wrap_line_count(block.body, inner_w))
	lines := ui.word_wrap_lines(block.body, inner_w, context.temp_allocator, CODE_PREVIEW_LINES)
	shown_body := min(total, CODE_PREVIEW_LINES)
	code_bg := t.code_bg
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
		spans := ui.highlight_line(block.lang, line, context.temp_allocator)
		cx := x0 + 3
		if len(spans) == 0 {
			ui.buffer_text_clip(buf, cx, row, x_end, line, t.assistant_fg, code_bg)
		} else {
			for sp in spans {
				if sp.start >= len(line) || sp.end <= sp.start {
					continue
				}
				end := min(sp.end, len(line))
				chunk := line[sp.start:end]
				ui.buffer_text_clip(buf, cx, row, x_end, chunk, ui.hl_color(sp.kind, t), code_bg)
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
