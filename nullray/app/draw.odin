// SPDX-License-Identifier: 0BSD
/*
Main TUI paint and overlay chrome.
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
	mode_chip := agent.mode_string(a.session.agent_mode)
	counts := fmt.tprintf("%s · %d sess · %d live", mode_chip, a.banner_sess, a.banner_live)
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
	if a.show_status {
		app_draw_status_overlay(buf, a)
		a.dirty = false
		return
	}

	input_rows := app_input_rows(a, buf.width)
	msg_top := 2
	msg_bottom := buf.height - 3 - input_rows
	msg_h := max(msg_bottom - msg_top + 1, 1)

	lay := app_view_layout(a, buf.width, buf.height)
	app_expand_hits_clear(a)

	if !(lay.open && lay.overlay) {
		content_w := buf.width
		if lay.open && !lay.overlay {
			content_w = max(1, lay.split_x)
		}

		blocks := app_collect_blocks(a, accent)
		heights := make([]int, len(blocks), context.temp_allocator)
		total_h := 0
		frozen_n := layout_frozen_count(a, blocks)
		reuse := layout_cache_key_match(a, content_w, accent) && a.layout_cache.frozen_count == frozen_n
		for b, i in blocks {
			if reuse && i < frozen_n {
				heights[i] = a.layout_cache.frozen_heights[i]
			} else {
				heights[i] = block_height(b, content_w)
			}
			total_h += heights[i]
		}
		layout_cache_store_frozen(a, heights, frozen_n, content_w, accent)

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
		app_draw_blocks(a, buf, blocks, heights, msg_top, msg_h, skip, t.accent, t.bg, 0, content_w)
	}

	if lay.open {
		app_draw_view_pane(buf, a, lay)
	}

	ui.buffer_hline(buf, 0, buf.height - 2 - input_rows, buf.width, '─', t.border, t.bg)

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
	status_y := buf.height - 1 - input_rows
	ui.draw_status_bar_ex(buf, status_y, status_left, help, status_fg, t.muted, t.status_bg)

	cap_x1 := buf.width - 1
	if lay.open && !lay.overlay {
		cap_x1 = max(0, lay.split_x - 1)
	}
	app_sel_capture_buffer(a, buf, msg_top, msg_bottom, 0, cap_x1)

	app_draw_input_box(buf, a, buf.height - input_rows, input_rows, t.fg, t.input_bg, t.accent)
	app_draw_suggestions(buf, a)
	app_apply_selection_style(buf, a)
	app_draw_toasts(buf, a)
	app_draw_elevate_modal(buf, a)

	a.dirty = false
}

@(private)
app_draw_status_overlay :: proc(buf: ^ui.Buffer, a: ^App) {
	t := ui.theme()
	body := a.status_body
	lines := strings.split_lines(body, context.temp_allocator)
	view_h := max(1, buf.height - 5)
	max_scroll := max(0, len(lines) - view_h)
	if a.status_scroll > max_scroll {
		a.status_scroll = max_scroll
	}
	y := 2
	for i := a.status_scroll; i < len(lines) && y < buf.height - 3; i += 1 {
		ui.buffer_fill_rect(buf, 0, y, buf.width, 1, ' ', t.fg, t.bg)
		ui.buffer_text_clip(buf, 1, y, buf.width - 1, lines[i], t.fg, t.bg)
		y += 1
	}
	ui.buffer_hline(buf, 0, buf.height - 3, buf.width, '─', t.border, t.bg)
	help_right := "PgUp/PgDn · Esc close"
	if max_scroll > 0 {
		help_right = fmt.tprintf("%d/%d · %s", a.status_scroll + 1, max_scroll + 1, help_right)
	}
	ui.draw_status_bar_ex(buf, buf.height - 2, "status", help_right, t.status_fg, t.muted, t.status_bg)
	ui.draw_input_line(buf, buf.height - 1, "❯ ", strings.to_string(a.input), a.cursor, t.fg, t.input_bg, t.accent)
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
	input_rows := app_input_rows(a, buf.width)
	hint := slash_arg_hint(text)
	if len(hint) > 0 {
		y := buf.height - 1 - input_rows
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
	start_y := buf.height - 1 - input_rows - max_show
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
