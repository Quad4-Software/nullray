/*
Transcript collection and TUI paint.
*/

package app

import "core:fmt"
import "core:strings"
import "nullray:config"
import "nullray:constants"
import "nullray:provider"
import "nullray:session"
import "nullray:ui"

Transcript_Block :: struct {
	prefix:       string,
	body:         string,
	prefix_fg:    ui.Color,
	body_fg:      ui.Color,
	prefix_style: ui.Style,
	body_style:   ui.Style,
	caret:        bool,
	is_code:      bool,
	lang:         string,
	is_md:        bool,
}

CODE_PREVIEW_LINES :: 16

@(private)
block_body_width :: proc(buf_width: int, prefix: string) -> int {
	return max(1, buf_width - 1 - ui.string_cols(prefix) - 1)
}

@(private)
block_height :: proc(block: Transcript_Block, buf_width: int) -> int {
	bw := block_body_width(buf_width, block.prefix)
	if block.is_code {
		lines := ui.wrap_line_count(block.body, max(1, buf_width - 4))
		if lines <= 0 {
			lines = 1
		}
		// header + body (capped)
		shown := min(lines, CODE_PREVIEW_LINES)
		if lines > CODE_PREVIEW_LINES {
			shown += 1 // "... N more"
		}
		return 1 + shown
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
app_append_md_content :: proc(
	blocks: ^[dynamic]Transcript_Block,
	label_prefix: string,
	content: string,
	accent: ui.Color,
	fg: ui.Color,
	caret: bool,
) {
	t := ui.theme()
	if len(content) == 0 {
		append(blocks, Transcript_Block{
			prefix = label_prefix,
			body = "",
			prefix_fg = accent,
			body_fg = fg,
			prefix_style = {.Bold},
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
			})
		case .Heading:
			pfx := ""
			if first {
				pfx = label_prefix
			}
			append(blocks, Transcript_Block{
				prefix = pfx,
				body = b.body,
				prefix_fg = accent,
				body_fg = t.title,
				prefix_style = {.Bold},
				body_style = {.Bold},
				caret = caret && is_last,
				is_md = true,
			})
			first = false
		case .Quote:
			pfx := "│ "
			style: ui.Style = {.Dim}
			pfg := t.muted
			if first {
				pfx = label_prefix
				pfg = accent
				style = {.Bold}
			}
			append(blocks, Transcript_Block{
				prefix = pfx,
				body = b.body,
				prefix_fg = pfg,
				body_fg = t.muted,
				prefix_style = style,
				body_style = {.Dim},
				caret = caret && is_last,
				is_md = true,
			})
			first = false
		case .List_Item:
			pfx := "  • "
			pfg := t.muted
			pstyle: ui.Style
			if first {
				pfx = label_prefix
				pfg = accent
				pstyle = {.Bold}
			}
			append(blocks, Transcript_Block{
				prefix = pfx,
				body = b.body,
				prefix_fg = pfg,
				body_fg = fg,
				prefix_style = pstyle,
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
			if first {
				pfx = label_prefix
				pstyle = {.Bold}
			}
			append(blocks, Transcript_Block{
				prefix = pfx,
				body = b.body,
				prefix_fg = accent,
				body_fg = fg,
				prefix_style = pstyle,
				caret = caret && is_last,
				is_md = true,
			})
			first = false
		}
	}
}

@(private)
app_collect_blocks :: proc(a: ^App, accent: ui.Color, allocator := context.temp_allocator) -> []Transcript_Block {
	t := ui.theme()
	blocks := make([dynamic]Transcript_Block, 0, len(a.session.messages) + 4, allocator)
	for m in a.session.messages {
		label := "you"
		fg := t.user_fg
		render_md := false
		if m.role == .Assistant {
			label = "nullray"
			fg = t.assistant_fg
			render_md = true
		} else if m.role == .System {
			label = "sys"
			fg = t.muted
		} else if m.role == .Tool {
			label = "tool"
			if len(m.name) > 0 {
				label = fmt.tprintf("tool:%s", m.name)
			}
			fg = t.muted
		}
		if m.role == .Assistant && len(m.reasoning) > 0 {
			append(&blocks, Transcript_Block{
				prefix = "think: ",
				body = m.reasoning,
				prefix_fg = t.muted,
				body_fg = t.muted,
				prefix_style = {.Dim},
				body_style = {.Dim},
			})
		}
		pfx := fmt.tprintf("%s: ", label)
		if render_md {
			app_append_md_content(&blocks, pfx, m.content, accent, fg, false)
		} else {
			append(&blocks, Transcript_Block{
				prefix = pfx,
				body = m.content,
				prefix_fg = accent,
				body_fg = fg,
				prefix_style = {.Bold},
				is_md = true,
			})
		}
	}

	if a.session.has_thinking {
		append(&blocks, Transcript_Block{
			prefix = "think: ",
			body = strings.to_string(a.session.thinking),
			prefix_fg = t.muted,
			body_fg = t.muted,
			prefix_style = {.Dim},
			body_style = {.Dim},
		})
	}
	if a.session.has_streaming {
		stream_accent := ui.color_lerp(t.accent_dim, t.accent, ui.anim_pulse(1200))
		app_append_md_content(&blocks, "nullray: ", strings.to_string(a.session.streaming), stream_accent, t.assistant_fg, true)
	} else if a.session.busy && !a.session.has_thinking {
		append(&blocks, Transcript_Block{
			prefix = "nullray: ",
			body = fmt.tprintf("%s waiting…", ui.spinner_frame(&a.spinner)),
			prefix_fg = accent,
			body_fg = t.muted,
			prefix_style = {.Bold},
			body_style = {.Dim},
		})
	} else if a.session.busy {
		append(&blocks, Transcript_Block{
			prefix = "nullray: ",
			body = "…",
			prefix_fg = accent,
			body_fg = t.muted,
			prefix_style = {.Bold},
		})
	}
	return blocks[:]
}

@(private)
app_draw_blocks :: proc(
	buf: ^ui.Buffer,
	blocks: []Transcript_Block,
	msg_top, msg_h, skip_lines: int,
	caret_fg, caret_bg: ui.Color,
) {
	t := ui.theme()
	skip := skip_lines
	y := msg_top
	remain := msg_h
	for block in blocks {
		if remain <= 0 {
			break
		}
		h := block_height(block, buf.width)
		if skip >= h {
			skip -= h
			continue
		}
		local_skip := skip
		skip = 0

		if block.is_code {
			used := app_draw_code_block(buf, block, y, remain, local_skip)
			y += used
			remain -= used
			continue
		}

		bw := block_body_width(buf.width, block.prefix)
		px := 1 + ui.string_cols(block.prefix)

		if local_skip == 0 && len(block.prefix) > 0 {
			ui.buffer_text(buf, 1, y, block.prefix, block.prefix_fg, t.bg, block.prefix_style)
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
			used = ui.draw_md_text_wrapped(buf, px, y, bw, remain, body, block.body_fg, t.accent, t.bg, block.body_style, local_skip)
		} else {
			used = ui.draw_wrapped_text_skip(buf, px, y, bw, remain, body, local_skip, block.body_fg, t.bg, block.body_style)
		}
		if used <= 0 {
			used = 1
			if local_skip == 0 {
				ui.buffer_text(buf, px, y, body, block.body_fg, t.bg, block.body_style)
			}
		}
		if block.caret && local_skip + used >= block_height(block, buf.width) {
			end_col := ui.wrap_last_line_cols(ui.md_strip_inline_ticks(body), bw)
			ui.draw_stream_caret(buf, px, y + used - 1, end_col, caret_fg, caret_bg)
		}
		y += used
		remain -= used
	}
}

@(private)
app_draw_code_block :: proc(buf: ^ui.Buffer, block: Transcript_Block, y, remain, local_skip: int) -> int {
	t := ui.theme()
	if remain <= 0 {
		return 0
	}
	width := max(1, buf.width - 4)
	lines := ui.word_wrap_lines(block.body, width, context.temp_allocator)
	total := len(lines)
	if total == 0 {
		total = 1
	}
	shown_body := min(total, CODE_PREVIEW_LINES)
	extra := 0
	if total > CODE_PREVIEW_LINES {
		extra = 1
	}
	full_h := 1 + shown_body + extra
	used := 0
	vis := 0

	// Header
	if local_skip == 0 && used < remain {
		hdr := fmt.tprintf("┌ %s ", block.lang)
		ui.buffer_fill_rect(buf, 0, y, buf.width, 1, ' ', t.muted, t.highlight_bg)
		ui.buffer_text_clip(buf, 1, y, buf.width - 1, hdr, t.accent, t.highlight_bg, {.Bold})
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
		ui.buffer_fill_rect(buf, 0, row, buf.width, 1, ' ', t.fg, t.highlight_bg)
		ui.buffer_text(buf, 1, row, "│ ", t.muted, t.highlight_bg)
		spans := ui.highlight_line(block.lang, line, context.temp_allocator)
		cx := 3
		if len(spans) == 0 {
			ui.buffer_text_clip(buf, cx, row, buf.width - 1, line, t.assistant_fg, t.highlight_bg)
		} else {
			for sp in spans {
				if sp.start >= len(line) || sp.end <= sp.start {
					continue
				}
				end := min(sp.end, len(line))
				chunk := line[sp.start:end]
				ui.buffer_text_clip(buf, cx, row, buf.width - 1, chunk, ui.hl_color(sp.kind, t), t.highlight_bg)
				cx += ui.string_cols(chunk)
				if cx >= buf.width - 1 {
					break
				}
			}
		}
		used += 1
		vis += 1
	}
	if total > CODE_PREVIEW_LINES && used < remain {
		if !(local_skip > 0 && vis < local_skip) {
			more := fmt.tprintf("└ … %d more lines", total - CODE_PREVIEW_LINES)
			ui.buffer_fill_rect(buf, 0, y + used, buf.width, 1, ' ', t.muted, t.highlight_bg)
			ui.buffer_text_clip(buf, 1, y + used, buf.width - 1, more, t.muted, t.highlight_bg, {.Dim})
			used += 1
		}
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
	t := ui.theme()
	p := provider.registry_active(&a.registry)

	title := constants.APP_NAME
	accent := ui.color_lerp(t.accent_dim, t.accent, ui.anim_pulse(1800))
	ver := fmt.tprintf("? · %s", constants.VERSION)
	ui.draw_status_bar(buf, 0, title, ver, t.title, t.status_bg)
	a.help_btn_x = max(1, buf.width - ui.string_cols(ver) - 1)
	if p != nil {
		sess := a.session.name
		if len(sess) == 0 {
			sess = "default"
		}
		right := fmt.tprintf("%s · %s · %s", p.name, p.default_model, sess)
		if len(a.session.group) > 0 {
			right = fmt.tprintf("%s · g:%s", right, a.session.group)
		}
		if !a.session.persist {
			right = fmt.tprintf("%s · ephemeral", right)
		}
		if len(a.credits_label) > 0 {
			right = fmt.tprintf("%s · %s", right, a.credits_label)
		}
		ui.buffer_text_clip(buf, max(string_cols_safe(title) + 3, 1), 0, a.help_btn_x - 1, right, t.muted, t.status_bg)
	}
	// Emphasize the ? hit target
	ui.buffer_text(buf, a.help_btn_x, 0, "?", t.accent, t.status_bg, {.Bold})

	ui.buffer_hline(buf, 0, 1, buf.width, '─', t.border, t.bg)

	if a.show_help {
		app_draw_help(buf, a)
		a.dirty = false
		return
	}

	msg_top := 2
	msg_bottom := buf.height - 3
	msg_h := max(msg_bottom - msg_top + 1, 1)

	blocks := app_collect_blocks(a, accent)
	total_h := 0
	for b in blocks {
		total_h += block_height(b, buf.width)
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
	app_draw_blocks(buf, blocks, msg_top, msg_h, skip, t.accent, t.bg)

	status_left := a.session.status
	if a.session.busy {
		status_left = fmt.tprintf("%s %s", ui.spinner_frame(&a.spinner), a.session.status)
		if !a.follow {
			status_left = fmt.tprintf("%s · End to follow", status_left)
		}
	} else if strings.has_prefix(a.session.status, "error") {
		status_left = a.session.status
	} else if a.session.last_usage.total_tokens > 0 {
		status_left = session.session_ready_status(&a.session)
	}
	help := "type / · ? help · ^q quit"
	ui.draw_status_bar(buf, buf.height - 2, status_left, help, t.status_fg, t.status_bg)

	text := strings.to_string(a.input)
	ui.draw_input_line(buf, buf.height - 1, "> ", text, a.cursor, t.fg, t.input_bg, t.accent)
	app_draw_suggestions(buf, a)

	a.dirty = false
}

@(private)
app_draw_help :: proc(buf: ^ui.Buffer, a: ^App) {
	t := ui.theme()
	binds_help := config.binds_help_text(a.binds, context.temp_allocator)
	body := help_overlay_text(binds_help, context.temp_allocator)
	y := 2
	for line in strings.split_lines(body, context.temp_allocator) {
		if y >= buf.height - 2 {
			break
		}
		ui.buffer_fill_rect(buf, 0, y, buf.width, 1, ' ', t.fg, t.bg)
		ui.buffer_text_clip(buf, 1, y, buf.width - 1, line, t.fg, t.bg)
		y += 1
	}
	ui.draw_status_bar(buf, buf.height - 2, "help", "Esc/? close", t.status_fg, t.status_bg)
	ui.draw_input_line(buf, buf.height - 1, "> ", strings.to_string(a.input), a.cursor, t.fg, t.input_bg, t.accent)
}

@(private)
app_draw_suggestions :: proc(buf: ^ui.Buffer, a: ^App) {
	text := strings.to_string(a.input)
	matches := slash_matches(text)
	if len(matches) == 0 {
		return
	}
	t := ui.theme()
	max_show := min(len(matches), 6)
	start_y := buf.height - 2 - max_show
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
		line := fmt.tprintf("/%-12s %s", cmd.name, cmd.help)
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
