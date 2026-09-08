// SPDX-License-Identifier: 0BSD
/*
Transcript collection and TUI paint.
*/

package app

import "core:fmt"
import "core:path/filepath"
import "core:strings"
import "nullray:agent"
import "nullray:config"
import "nullray:constants"
import "nullray:provider"
import "nullray:session"
import "nullray:subagent"
import "nullray:tools"
import "nullray:ui"

Transcript_Block :: struct {
	prefix:       string,
	body:         string,
	prefix_fg:    ui.Color,
	body_fg:      ui.Color,
	prefix_style: ui.Style,
	body_style:   ui.Style,
	row_bg:       ui.Color,
	has_bg:       bool,
	gutter:       bool,
	gap:          bool,
	caret:        bool,
	is_code:      bool,
	lang:         string,
	is_md:        bool,
}

CODE_PREVIEW_LINES :: 16
CONTENT_X :: 2

@(private)
block_body_width :: proc(buf_width: int, prefix: string) -> int {
	return max(1, buf_width - CONTENT_X - ui.string_cols(prefix) - 1)
}

@(private)
block_height :: proc(block: Transcript_Block, buf_width: int) -> int {
	if block.gap {
		return 1
	}
	bw := block_body_width(buf_width, block.prefix)
	if block.is_code {
		lines := ui.wrap_line_count(block.body, max(1, buf_width - 5))
		if lines <= 0 {
			lines = 1
		}
		shown := min(lines, CODE_PREVIEW_LINES)
		// header + body + footer
		return 2 + shown
	}
	if len(block.body) == 0 {
		return 1
	}
	if block.is_md {
		return max(1, ui.md_text_line_count(block.body, bw))
	}
	return max(1, ui.wrap_line_count(block.body, bw))
}

@(private)
app_append_gap :: proc(blocks: ^[dynamic]Transcript_Block) {
	if len(blocks) == 0 {
		return
	}
	last := blocks[len(blocks) - 1]
	if last.gap {
		return
	}
	append(blocks, Transcript_Block{gap = true})
}

@(private)
app_append_md_content :: proc(
	blocks: ^[dynamic]Transcript_Block,
	label_prefix: string,
	content: string,
	accent: ui.Color,
	fg: ui.Color,
	caret: bool,
	row_bg: ui.Color = {},
	has_bg: bool = false,
	gutter: bool = false,
) {
	t := ui.theme()
	if len(content) == 0 {
		append(blocks, Transcript_Block{
			prefix = label_prefix,
			body = "",
			prefix_fg = accent,
			body_fg = fg,
			prefix_style = {.Bold},
			row_bg = row_bg,
			has_bg = has_bg,
			gutter = gutter,
			caret = caret,
			is_md = true,
		})
		return
	}
	md := ui.md_parse(content, context.temp_allocator)
	if len(md) == 0 {
		append(blocks, Transcript_Block{
			prefix = label_prefix,
			body = content,
			prefix_fg = accent,
			body_fg = fg,
			prefix_style = {.Bold},
			row_bg = row_bg,
			has_bg = has_bg,
			gutter = gutter,
			caret = caret,
			is_md = true,
		})
		return
	}
	first := true
	for b, idx in md {
		is_last := idx == len(md) - 1
		switch b.kind {
		case .Blank:
			continue
		case .Hr:
			append(blocks, Transcript_Block{
				prefix = "",
				body = "────────",
				prefix_fg = t.muted,
				body_fg = t.muted,
				body_style = {.Dim},
				row_bg = row_bg,
				has_bg = has_bg,
			})
		case .Heading:
			pfx := ""
			g := false
			if first {
				pfx = label_prefix
				g = gutter
			}
			append(blocks, Transcript_Block{
				prefix = pfx,
				body = b.body,
				prefix_fg = accent,
				body_fg = t.title,
				prefix_style = {.Bold},
				body_style = {.Bold},
				row_bg = row_bg,
				has_bg = has_bg,
				gutter = g,
				caret = caret && is_last,
				is_md = true,
			})
			first = false
		case .Quote:
			pfx := "│ "
			style: ui.Style = {.Dim}
			pfg := t.muted
			g := false
			if first {
				pfx = label_prefix
				pfg = accent
				style = {.Bold}
				g = gutter
			}
			append(blocks, Transcript_Block{
				prefix = pfx,
				body = b.body,
				prefix_fg = pfg,
				body_fg = t.muted,
				prefix_style = style,
				body_style = {.Dim},
				row_bg = row_bg,
				has_bg = has_bg,
				gutter = g,
				caret = caret && is_last,
				is_md = true,
			})
			first = false
		case .List_Item:
			pfx := "  • "
			pfg := t.muted
			pstyle: ui.Style
			g := false
			if first {
				pfx = label_prefix
				pfg = accent
				pstyle = {.Bold}
				g = gutter
			}
			append(blocks, Transcript_Block{
				prefix = pfx,
				body = b.body,
				prefix_fg = pfg,
				body_fg = fg,
				prefix_style = pstyle,
				row_bg = row_bg,
				has_bg = has_bg,
				gutter = g,
				caret = caret && is_last,
				is_md = true,
			})
			first = false
		case .Code:
			lang := b.lang
			if len(lang) == 0 {
				lang = "code"
			}
			append(blocks, Transcript_Block{
				prefix = "",
				body = b.body,
				prefix_fg = t.muted,
				body_fg = t.assistant_fg,
				is_code = true,
				lang = lang,
				caret = caret && is_last,
			})
			first = false
		case .Text:
			pfx := ""
			pstyle: ui.Style
			g := false
			if first {
				pfx = label_prefix
				pstyle = {.Bold}
				g = gutter
			}
			append(blocks, Transcript_Block{
				prefix = pfx,
				body = b.body,
				prefix_fg = accent,
				body_fg = fg,
				prefix_style = pstyle,
				row_bg = row_bg,
				has_bg = has_bg,
				gutter = g,
				caret = caret && is_last,
				is_md = true,
			})
			first = false
		}
	}
}

@(private)
tool_artifact_stub :: proc(content: string, allocator := context.allocator) -> (string, bool) {
	idx := strings.index(content, "artifact=")
	if idx < 0 {
		return "", false
	}
	rest := content[idx + len("artifact="):]
	end := 0
	for end < len(rest) {
		c := rest[end]
		if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-' || c == '_' {
			end += 1
			continue
		}
		break
	}
	if end == 0 {
		return "", false
	}
	id := rest[:end]
	head := content
	nl := strings.index_byte(content, '\n')
	if nl > 0 {
		head = content[:nl]
	}
	if len(head) > 120 {
		head = head[:120]
	}
	return fmt.aprintf("%s (expand: /artifact %s)", head, id, allocator = allocator), true
}

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
		if m.role == .Tool {
			if stub, ok := tool_artifact_stub(m.content, context.temp_allocator); ok {
				body = stub
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
			used := app_draw_code_block(buf, block, y, remain, local_skip, area_x, content_w)
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

app_draw :: proc(buf: ^ui.Buffer, user: rawptr) {
	a := cast(^App)user
	if splash_active(a) {
		app_draw_splash(buf, a)
		a.dirty = false
		return
	}
	if a.show_setup {
		app_draw_setup(buf, a)
		a.dirty = false
		return
	}
	t := ui.theme()
	p := provider.registry_active(&a.registry)

	title := constants.APP_NAME
	accent := ui.color_lerp(t.accent_dim, t.accent, ui.anim_pulse(1800))
	ver := fmt.tprintf("?  %s", constants.VERSION)
	ui.draw_status_bar(buf, 0, title, ver, t.title, t.status_bg)
	a.help_btn_x = max(1, buf.width - ui.string_cols(ver) - 1)

	mid_x := max(string_cols_safe(title) + 2, 1)
	counts := fmt.tprintf("%d sess · %d live", a.banner_sess, a.banner_live)
	count_end := mid_x + ui.string_cols(counts) + 2
	ui.buffer_text_clip(buf, mid_x, 0, min(count_end, a.help_btn_x - 1), counts, t.accent, t.status_bg)

	if p != nil {
		sess := a.session.name
		if len(sess) == 0 {
			sess = "default"
		}
		right := fmt.tprintf("%s · %s · %s", p.name, p.default_model, sess)
		if agents := subagent.roster_compact_line(&a.subagents.roster, context.temp_allocator); len(agents) > 0 {
			right = fmt.tprintf("%s · %s", right, agents)
		}
		if subagent.policy_is_locked() || a.subagents.model_locked {
			right = fmt.tprintf("%s · lock", right)
		}
		if len(a.session.group) > 0 {
			right = fmt.tprintf("%s · g:%s", right, a.session.group)
		}
		if !a.session.persist {
			right = fmt.tprintf("%s · ephemeral", right)
		}
		if !a.hide_sensitive && len(a.credits_label) > 0 {
			right = fmt.tprintf("%s · %s", right, a.credits_label)
		}
		info_x := max(count_end + 1, mid_x)
		ui.buffer_text_clip(buf, info_x, 0, a.help_btn_x - 1, right, t.muted, t.status_bg)
	}
	ui.buffer_text(buf, a.help_btn_x, 0, "?", t.accent, t.status_bg, {.Bold})

	ui.buffer_hline(buf, 0, 1, buf.width, '─', t.border, t.bg)

	if a.show_help {
		app_draw_help(buf, a)
		a.dirty = false
		return
	}

	msg_top := 2
	msg_bottom := buf.height - 4
	msg_h := max(msg_bottom - msg_top + 1, 1)

	lay := app_view_layout(a, buf.width, buf.height)

	if !(lay.open && lay.overlay) {
		content_w := buf.width
		if lay.open && !lay.overlay {
			content_w = max(1, lay.split_x)
		}

		blocks := app_collect_blocks(a, accent)
		heights := make([]int, len(blocks), context.temp_allocator)
		total_h := 0
		for b, i in blocks {
			heights[i] = block_height(b, content_w)
			total_h += heights[i]
		}

		if a.follow {
			a.scroll = 0
		}
		max_scroll := max(0, total_h - msg_h)
		if a.scroll > max_scroll {
			a.scroll = max_scroll
		}
		if a.scroll == 0 {
			a.follow = true
		}
		skip := max(0, total_h - msg_h - a.scroll)
		app_draw_blocks(buf, blocks, heights, msg_top, msg_h, skip, t.accent, t.bg, 0, content_w)
	}

	if lay.open {
		app_draw_view_pane(buf, a, lay)
	}

	ui.buffer_hline(buf, 0, buf.height - 3, buf.width, '─', t.border, t.bg)

	status_left := a.session.status
	status_fg := t.status_fg
	if a.elevate_active {
		status_left = "elevate: waiting for password · Esc cancel"
		status_fg = t.warn
	} else if pending := tools.shell_pending(context.temp_allocator); len(pending) > 0 {
		status_left = fmt.tprintf("shell: %s · /allow /deny", pending)
		status_fg = t.warn
	} else if a.session.busy {
		status_left = fmt.tprintf("%s %s", ui.spinner_frame(&a.spinner), a.session.status)
		if !a.follow {
			status_left = fmt.tprintf("%s · End to follow", status_left)
		}
		status_fg = t.accent
	} else if strings.has_prefix(a.session.status, "error") {
		status_left = a.session.status
		status_fg = t.error
	} else if a.view_open {
		base := filepath.base(a.view_path)
		if len(a.view_recent) > 1 {
			status_left = fmt.tprintf("view: %s (%d/%d)", base, a.view_idx + 1, len(a.view_recent))
		} else {
			status_left = fmt.tprintf("view: %s", base)
		}
		if a.view_focus {
			status_left = fmt.tprintf("%s · focus", status_left)
		}
		status_fg = t.accent
	} else if a.session.last_usage.total_tokens > 0 {
		status_left = session.session_ready_status(&a.session)
	}
	help := "type / · ? help · ^q quit"
	if a.view_open {
		help = "Tab focus · [ ] files · Esc close"
	} else if a.sel_has || a.sel_dragging {
		help = "drag select · /copy · Esc clear"
	}
	ui.draw_status_bar_ex(buf, buf.height - 2, status_left, help, status_fg, t.muted, t.status_bg)

	cap_x1 := buf.width - 1
	if lay.open && !lay.overlay {
		cap_x1 = max(0, lay.split_x - 1)
	}
	app_sel_capture_buffer(a, buf, msg_top, msg_bottom, 0, cap_x1)

	text := strings.to_string(a.input)
	ui.draw_input_line(buf, buf.height - 1, "❯ ", text, a.cursor, t.fg, t.input_bg, t.accent)
	app_draw_suggestions(buf, a)
	app_apply_selection_style(buf, a)
	app_draw_toasts(buf, a)
	app_draw_elevate_modal(buf, a)

	a.dirty = false
}

@(private)
app_draw_help :: proc(buf: ^ui.Buffer, a: ^App) {
	t := ui.theme()
	binds_help := config.binds_help_text(a.binds, a.keys_preset, context.temp_allocator)
	body := help_overlay_text(binds_help, context.temp_allocator)
	lines := strings.split_lines(body, context.temp_allocator)
	view_h := max(1, buf.height - 5)
	max_scroll := max(0, len(lines) - view_h)
	if a.help_scroll > max_scroll {
		a.help_scroll = max_scroll
	}
	y := 2
	for i := a.help_scroll; i < len(lines) && y < buf.height - 3; i += 1 {
		ui.buffer_fill_rect(buf, 0, y, buf.width, 1, ' ', t.fg, t.bg)
		ui.buffer_text_clip(buf, 1, y, buf.width - 1, lines[i], t.fg, t.bg)
		y += 1
	}
	ui.buffer_hline(buf, 0, buf.height - 3, buf.width, '─', t.border, t.bg)
	help_right := "PgUp/PgDn · Esc/? close"
	if max_scroll > 0 {
		help_right = fmt.tprintf("%d/%d · %s", a.help_scroll + 1, max_scroll + 1, help_right)
	}
	ui.draw_status_bar_ex(buf, buf.height - 2, "help", help_right, t.status_fg, t.muted, t.status_bg)
	ui.draw_input_line(buf, buf.height - 1, "❯ ", strings.to_string(a.input), a.cursor, t.fg, t.input_bg, t.accent)
}

@(private)
app_draw_suggestions :: proc(buf: ^ui.Buffer, a: ^App) {
	text := strings.to_string(a.input)
	t := ui.theme()
	hint := slash_arg_hint(text)
	if len(hint) > 0 {
		y := buf.height - 3
		if y < 2 {
			y = 2
		}
		ui.buffer_fill_rect(buf, 0, y, buf.width, 1, ' ', t.highlight_fg, t.highlight_bg)
		ui.buffer_text_clip(buf, 1, y, buf.width - 1, hint, t.accent, t.highlight_bg, {.Bold})
		return
	}
	matches := slash_matches(text)
	if len(matches) == 0 {
		return
	}
	max_show := min(len(matches), 6)
	start_y := buf.height - 3 - max_show
	if start_y < 2 {
		start_y = 2
	}
	sel := a.suggest_sel
	if sel < 0 {
		sel = 0
	}
	if sel >= len(matches) {
		sel = len(matches) - 1
	}
	for i in 0 ..< max_show {
		cmd := matches[i]
		y := start_y + i
		line := fmt.tprintf("%-28s %s", cmd.usage, cmd.help)
		bg := t.highlight_bg
		fg := t.highlight_fg
		style: ui.Style
		if i == sel {
			style = {.Bold, .Reverse}
			fg = t.accent
		}
		ui.buffer_fill_rect(buf, 0, y, buf.width, 1, ' ', fg, bg)
		ui.buffer_text_clip(buf, 1, y, buf.width - 1, line, fg, bg, style)
	}
}

string_cols_safe :: proc(s: string) -> int {
	return ui.string_cols(s)
}
