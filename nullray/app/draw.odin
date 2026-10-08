// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Main TUI paint and overlay chrome.
*/

package app

import "core:fmt"
import "core:path/filepath"
import "core:strings"
import "core:time"
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
	c := app_chrome(a, buf.width, buf.height)
	accent := ui.color_lerp(t.accent_dim, t.accent, ui.anim_pulse(1800))

	ver := app_chrome_ver_label(c)
	mid_x := app_draw_title_brand(buf, c, t)
	a.help_btn_x = max(1, buf.width - ui.string_cols(ver) - 1)
	ui.buffer_text_clip(buf, a.help_btn_x, c.title_y, buf.width, ver, t.accent, t.status_bg, {.Bold})

	mode_chip := agent.mode_string(a.session.agent_mode)
	counts := app_chrome_counts(a, c, mode_chip)
	count_end := mid_x + ui.string_cols(counts) + 1
	if count_end > a.help_btn_x - 1 {
		count_end = a.help_btn_x - 1
	}
	if mid_x < a.help_btn_x - 1 && len(counts) > 0 {
		ui.buffer_text_clip(buf, mid_x, c.title_y, min(count_end, a.help_btn_x - 1), counts, t.accent, t.status_bg)
	}

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
		if cl := app_credits_label(a); !a.hide_sensitive && len(cl) > 0 {
			right = fmt.tprintf("%s · %s", right, cl)
			delete(cl)
		}
		right = app_chrome_right_info(a, c, right)
		info_x := max(count_end + 1, mid_x)
		if len(right) > 0 && info_x < a.help_btn_x - 1 {
			ui.buffer_text_clip(buf, info_x, c.title_y, a.help_btn_x - 1, right, t.muted, t.status_bg)
		}
	}

	if c.show_tabs && c.tabs_y >= 0 {
		app_draw_tabs(buf, a, c.tabs_y)
	}
	if c.show_sep && c.sep_y >= 0 {
		ui.buffer_hline(buf, 0, c.sep_y, buf.width, '─', t.border, t.bg)
	}

	if a.show_help {
		app_draw_help(buf, a, c)
		a.dirty = false
		return
	}
	if a.show_status {
		app_draw_status_overlay(buf, a, c)
		a.dirty = false
		return
	}
	if a.show_history {
		app_draw_history(buf, a, c)
		a.dirty = false
		return
	}

	msg_top := c.msg_top
	msg_bottom := c.msg_bottom
	msg_h := app_chrome_msg_h(c)

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

	if c.status_y > c.msg_top {
		ui.buffer_hline(buf, 0, c.status_y - 1, buf.width, '─', t.border, t.bg)
	}

	status_left := a.session.status
	status_fg := t.status_fg
	if a.elevate_active {
		if c.narrow {
			status_left = "elevate · Esc"
		} else {
			status_left = "elevate: waiting for password · Esc cancel"
		}
		status_fg = t.warn
	} else if pending := tools.shell_pending(context.temp_allocator); len(pending) > 0 {
		if c.narrow {
			status_left = "shell · /allow"
		} else {
			status_left = fmt.tprintf("shell: %s · /allow /deny", pending)
		}
		status_fg = t.warn
	} else if a.session.busy {
		secs := int(time.tick_since(a.session.busy_since) / time.Second)
		if c.narrow {
			status_left = fmt.tprintf("%s %ds", ui.spinner_frame(&a.spinner), secs)
			if len(a.session.live_tool) > 0 {
				status_left = fmt.tprintf("%s · %s", status_left, a.session.live_tool)
			}
		} else {
			status_left = fmt.tprintf(
				"%s %s · %ds",
				ui.spinner_frame(&a.spinner),
				a.session.status,
				secs,
			)
			if len(a.session.live_tool) > 0 {
				status_left = fmt.tprintf("%s · %s", status_left, a.session.live_tool)
			}
			if !a.follow {
				status_left = fmt.tprintf("%s · End to follow", status_left)
			}
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
		status_left = session.session_ready_status(a.session)
	}
	help := app_chrome_help_right(a, c)
	ui.draw_status_bar_ex(buf, c.status_y, status_left, help, status_fg, t.muted, t.status_bg)

	cap_x1 := buf.width - 1
	if lay.open && !lay.overlay {
		cap_x1 = max(0, lay.split_x - 1)
	}
	app_sel_capture_buffer(a, buf, msg_top, msg_bottom, 0, cap_x1)

	app_draw_input_box(buf, a, c.input_y, c.input_rows, t.fg, t.input_bg, t.accent)
	app_draw_suggestions(buf, a, c)
	app_apply_selection_style(buf, a)
	app_draw_toasts(buf, a, c)
	app_draw_elevate_modal(buf, a)
	app_draw_ask_modal(buf, a)

	a.dirty = false
}

@(private)
app_draw_status_overlay :: proc(buf: ^ui.Buffer, a: ^App, c: Chrome) {
	t := ui.theme()
	body := a.status_body
	lines := strings.split_lines(body, context.temp_allocator)
	view_h := app_chrome_overlay_h(c)
	max_scroll := max(0, len(lines) - view_h)
	if a.status_scroll > max_scroll {
		a.status_scroll = max_scroll
	}
	y := c.msg_top
	end_y := c.status_y
	if c.status_y > c.msg_top {
		end_y = c.status_y - 1
	}
	for i := a.status_scroll; i < len(lines) && y < end_y; i += 1 {
		ui.buffer_fill_rect(buf, 0, y, buf.width, 1, ' ', t.fg, t.bg)
		ui.buffer_text_clip(buf, 1, y, buf.width - 1, lines[i], t.fg, t.bg)
		y += 1
	}
	if c.status_y > c.msg_top {
		ui.buffer_hline(buf, 0, c.status_y - 1, buf.width, '─', t.border, t.bg)
	}
	help_right := "PgUp/PgDn · Esc close"
	if c.narrow {
		help_right = "PgUp · Esc"
	}
	if max_scroll > 0 {
		help_right = fmt.tprintf("%d/%d · %s", a.status_scroll + 1, max_scroll + 1, help_right)
	}
	ui.draw_status_bar_ex(buf, c.status_y, "status", help_right, t.status_fg, t.muted, t.status_bg)
	app_draw_input_box(buf, a, c.input_y, c.input_rows, t.fg, t.input_bg, t.accent)
}

@(private)
app_draw_help :: proc(buf: ^ui.Buffer, a: ^App, c: Chrome) {
	t := ui.theme()
	binds_help := config.binds_help_text(a.binds, a.keys_preset, context.temp_allocator)
	body := help_overlay_text(binds_help, context.temp_allocator)
	lines := strings.split_lines(body, context.temp_allocator)
	view_h := app_chrome_overlay_h(c)
	max_scroll := max(0, len(lines) - view_h)
	if a.help_scroll > max_scroll {
		a.help_scroll = max_scroll
	}
	y := c.msg_top
	end_y := c.status_y
	if c.status_y > c.msg_top {
		end_y = c.status_y - 1
	}
	for i := a.help_scroll; i < len(lines) && y < end_y; i += 1 {
		ui.buffer_fill_rect(buf, 0, y, buf.width, 1, ' ', t.fg, t.bg)
		ui.buffer_text_clip(buf, 1, y, buf.width - 1, lines[i], t.fg, t.bg)
		y += 1
	}
	if c.status_y > c.msg_top {
		ui.buffer_hline(buf, 0, c.status_y - 1, buf.width, '─', t.border, t.bg)
	}
	help_right := "PgUp/PgDn · Esc/? close"
	if c.narrow {
		help_right = "PgUp · Esc"
	}
	if max_scroll > 0 {
		help_right = fmt.tprintf("%d/%d · %s", a.help_scroll + 1, max_scroll + 1, help_right)
	}
	ui.draw_status_bar_ex(buf, c.status_y, "help", help_right, t.status_fg, t.muted, t.status_bg)
	app_draw_input_box(buf, a, c.input_y, c.input_rows, t.fg, t.input_bg, t.accent)
}

@(private)
app_draw_suggestions :: proc(buf: ^ui.Buffer, a: ^App, c: Chrome) {
	text := strings.to_string(a.input)
	t := ui.theme()
	hint := slash_arg_hint(text)
	floor_y := max(c.msg_top, 1)
	if len(hint) > 0 {
		y := c.status_y
		if y < floor_y {
			y = floor_y
		}
		ui.buffer_fill_rect(buf, 0, y, buf.width, 1, ' ', t.highlight_fg, t.highlight_bg)
		ui.buffer_text_clip(buf, 1, y, buf.width - 1, hint, t.accent, t.highlight_bg, {.Bold})
		return
	}
	matches := slash_matches(text)
	if len(matches) == 0 {
		return
	}
	room := max(1, c.status_y - floor_y)
	max_show := min(len(matches), min(6, room))
	start_y := c.status_y - max_show
	if start_y < floor_y {
		start_y = floor_y
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
		if c.narrow {
			line = cmd.usage
		}
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
