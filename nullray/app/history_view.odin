// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Full session history overlay, opened with /history. Shows every message
in the session including thinking and reasoning text, word wrapped to
the terminal width and scrolled like the status overlay.
*/

package app

import "core:fmt"
import "core:strings"
import "nullray:agent"
import "nullray:provider"
import "nullray:session"
import "nullray:ui"

Hist_Line :: struct {
	text:  string,
	fg:    ui.Color,
	style: ui.Style,
}

@(private)
hist_push :: proc(out: ^[dynamic]Hist_Line, text: string, fg: ui.Color, style: ui.Style) {
	append(out, Hist_Line{text = text, fg = fg, style = style})
}

// Wrap body into out, one Hist_Line per visual row.
@(private)
hist_push_wrapped :: proc(
	out: ^[dynamic]Hist_Line,
	body: string,
	width: int,
	fg: ui.Color,
	style: ui.Style,
	allocator := context.temp_allocator,
) {
	lines := ui.word_wrap_lines(body, max(1, width), allocator)
	if len(lines) == 0 {
		hist_push(out, "", fg, style)
		return
	}
	for ln in lines {
		hist_push(out, ln, fg, style)
	}
}

@(private)
history_label :: proc(m: provider.Message, t: ui.Theme, accent: ui.Color) -> (text: string, fg: ui.Color) {
	switch m.role {
	case .User:
		if strings.has_prefix(m.content, agent.VERIFY_USER_PREFIX) {
			return "verify", t.warn
		}
		return "you", t.user_fg
	case .Assistant:
		return "nullray", accent
	case .System:
		return "sys", t.muted
	case .Tool:
		if len(m.name) > 0 {
			return fmt.tprintf("tool:%s", m.name), t.accent_dim
		}
		return "tool", t.accent_dim
	}
	return "?", t.muted
}

@(private)
history_body_color :: proc(m: provider.Message, t: ui.Theme) -> (fg: ui.Color, style: ui.Style) {
	switch m.role {
	case .User:
		fg = t.user_fg
	case .Assistant:
		fg = t.assistant_fg
	case .System, .Tool:
		fg = t.muted
		style = {.Dim}
	}
	if m.role == .User && strings.has_prefix(m.content, agent.VERIFY_USER_PREFIX) {
		fg = t.warn
	}
	if m.role == .Tool && session.looks_like_tool_error(m.content) {
		fg = t.error
		style = {}
	}
	return fg, style
}

/*
Build the full scrollback: one bold label line per message, wrapped body
lines, and a dim think section for reasoning. Thinking is labeled and
dimmed so it stays visually distinct from the reply body.
*/
history_view_lines :: proc(
	messages: []provider.Message,
	width: int,
	thinking: string,
	streaming: string,
	t: ui.Theme,
	accent: ui.Color,
	allocator := context.temp_allocator,
) -> []Hist_Line {
	out := make([dynamic]Hist_Line, 0, len(messages) * 4 + 8, allocator)
	wrap_w := max(1, width - 2)
	for m, i in messages {
		if i > 0 {
			hist_push(&out, "", t.muted, {})
		}
		label, lfg := history_label(m, t, accent)
		bfg, bstyle := history_body_color(m, t)
		hist_push(&out, label, lfg, {.Bold})
		if m.role == .Assistant && len(m.reasoning) > 0 {
			hist_push(&out, "think:", t.muted, {.Dim, .Bold})
			hist_push_wrapped(&out, m.reasoning, wrap_w, t.muted, {.Dim}, allocator)
		}
		hist_push_wrapped(&out, m.content, wrap_w, bfg, bstyle, allocator)
	}
	if len(thinking) > 0 {
		if len(out) > 0 {
			hist_push(&out, "", t.muted, {})
		}
		hist_push(&out, "nullray", accent, {.Bold})
		hist_push(&out, "think:", t.muted, {.Dim, .Bold})
		hist_push_wrapped(&out, thinking, wrap_w, t.muted, {.Dim}, allocator)
	}
	if len(streaming) > 0 {
		if len(out) > 0 {
			hist_push(&out, "", t.muted, {})
		}
		hist_push(&out, "nullray", accent, {.Bold})
		hist_push_wrapped(&out, streaming, wrap_w, t.assistant_fg, {}, allocator)
	}
	return out[:]
}

@(private)
app_history_line_count :: proc(a: ^App, width: int) -> int {
	t := ui.theme()
	return len(history_view_lines(
		a.session.messages[:],
		width,
		strings.to_string(a.session.thinking),
		strings.to_string(a.session.streaming),
		t,
		t.accent,
	))
}

slash_cmd_history :: proc(a: ^App, args: string) {
	_ = args
	a.show_history = true
	// Open at the bottom like a pager tail on the live session.
	width := 80
	height := 24
	if a.loop != nil {
		width = a.loop.term.width
		height = a.loop.term.height
	}
	c := app_chrome(a, width, height)
	view_h := app_chrome_overlay_h(c)
	a.history_scroll = max(0, app_history_line_count(a, width) - view_h)
	app_mark_dirty(a)
}

app_draw_history :: proc(buf: ^ui.Buffer, a: ^App, c: Chrome) {
	t := ui.theme()
	lines := history_view_lines(
		a.session.messages[:],
		buf.width,
		strings.to_string(a.session.thinking),
		strings.to_string(a.session.streaming),
		t,
		t.accent,
	)
	view_h := app_chrome_overlay_h(c)
	max_scroll := max(0, len(lines) - view_h)
	if a.history_scroll > max_scroll {
		a.history_scroll = max_scroll
	}
	if a.history_scroll < 0 {
		a.history_scroll = 0
	}
	y := c.msg_top
	end_y := c.status_y
	if c.status_y > c.msg_top {
		end_y = c.status_y - 1
	}
	if len(lines) == 0 {
		ui.buffer_text_clip(buf, 1, y, buf.width - 1, "empty session", t.muted, t.bg, {.Dim})
	}
	for i := a.history_scroll; i < len(lines) && y < end_y; i += 1 {
		ui.buffer_fill_rect(buf, 0, y, buf.width, 1, ' ', t.fg, t.bg)
		ui.buffer_text_clip(buf, 1, y, buf.width - 1, lines[i].text, lines[i].fg, t.bg, lines[i].style)
		y += 1
	}
	if c.status_y > c.msg_top {
		ui.buffer_hline(buf, 0, c.status_y - 1, buf.width, '─', t.border, t.bg)
	}
	help_right := "Up/PgUp, Home/End, Esc close"
	if c.narrow {
		help_right = "Up, Esc"
	}
	if max_scroll > 0 {
		help_right = fmt.tprintf("%d/%d, %s", a.history_scroll + 1, max_scroll + 1, help_right)
	}
	ui.draw_status_bar_ex(buf, c.status_y, "history", help_right, t.status_fg, t.muted, t.status_bg)
	app_draw_input_box(buf, a, c.input_y, c.input_rows, t.fg, t.input_bg, t.accent)
}
