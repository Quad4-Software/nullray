// SPDX-License-Identifier: 0BSD
/*
Setup wizard draw helpers and overlay.
*/

package app

import "core:fmt"
import "core:strings"
import "nullray:provider"
import "nullray:ui"

app_draw_setup :: proc(buf: ^ui.Buffer, a: ^App) {
	t := ui.theme()
	ui.buffer_clear(buf, t.bg, t.fg)
	title := "nullray setup"
	ui.draw_status_bar(buf, 0, title, "Tab/Enter next · Esc back", t.title, t.status_bg)
	ui.buffer_hline(buf, 0, 1, buf.width, '─', t.border, t.bg)

	y := 2
	step_name := "provider"
	switch a.setup_step {
	case .Provider:
		step_name = "1/5 provider (local / cloud)"
	case .Connection:
		step_name = "2/5 connection"
	case .Model:
		step_name = "3/5 model"
	case .Reasoning:
		step_name = "4/5 reasoning"
	case .Confirm:
		step_name = "5/5 confirm"
	}
	ui.buffer_text_clip(buf, 1, y, buf.width - 1, step_name, t.accent, t.bg, {.Bold})
	y += 2

	switch a.setup_step {
	case .Provider:
		setup_draw_provider_list(buf, a, y)
	case .Connection:
		setup_draw_connection(buf, a, y)
	case .Model:
		setup_draw_model(buf, a, y)
	case .Reasoning:
		setup_draw_reasoning(buf, a, y)
	case .Confirm:
		setup_draw_confirm(buf, a, y)
	}

	foot := a.setup_status
	if len(foot) == 0 {
		if a.setup_step == .Provider {
			foot = "local hosts first, then cloud APIs"
		} else {
			foot = "config first, then defaults"
		}
	}
	ui.draw_status_bar(buf, buf.height - 1, foot, "/setup later", t.status_fg, t.status_bg)
}

Setup_Prov_Row_Kind :: enum {
	Header,
	Item,
}

Setup_Prov_Row :: struct {
	kind:         Setup_Prov_Row_Kind,
	label:        string,
	provider_idx: int,
}

@(private)
setup_provider_live_badge :: proc(a: ^App, id: string) -> string {
	switch id {
	case "ollama":
		if a.ollama_live {
			return " live"
		}
	case "lmstudio":
		if a.lmstudio_live {
			return " live"
		}
	case "llamacpp":
		if a.llamacpp_live {
			return " live"
		}
	}
	return ""
}

@(private)
setup_provider_rows :: proc(a: ^App, allocator := context.temp_allocator) -> []Setup_Prov_Row {
	rows := make([dynamic]Setup_Prov_Row, allocator)
	local_n := 0
	cloud_n := 0
	for p in a.registry.providers {
		if provider.provider_is_local(p.id) {
			local_n += 1
		} else {
			cloud_n += 1
		}
	}
	if local_n > 0 {
		append(&rows, Setup_Prov_Row{kind = .Header, label = "Local", provider_idx = -1})
		for p, i in a.registry.providers {
			if provider.provider_is_local(p.id) {
				append(&rows, Setup_Prov_Row{kind = .Item, label = "", provider_idx = i})
			}
		}
	}
	if cloud_n > 0 {
		append(&rows, Setup_Prov_Row{kind = .Header, label = "Cloud", provider_idx = -1})
		for p, i in a.registry.providers {
			if !provider.provider_is_local(p.id) {
				append(&rows, Setup_Prov_Row{kind = .Item, label = "", provider_idx = i})
			}
		}
	}
	return rows[:]
}

@(private)
setup_provider_sel_row :: proc(rows: []Setup_Prov_Row, provider_idx: int) -> int {
	for row, i in rows {
		if row.kind == .Item && row.provider_idx == provider_idx {
			return i
		}
	}
	return 0
}

@(private)
setup_provider_move :: proc(a: ^App, delta: int) {
	rows := setup_provider_rows(a)
	if len(rows) == 0 {
		return
	}
	cur := setup_provider_sel_row(rows, a.setup_provider_sel)
	next := cur
	step := 1 if delta > 0 else -1
	remain := abs(delta)
	for remain > 0 {
		next += step
		if next < 0 || next >= len(rows) {
			break
		}
		if rows[next].kind == .Item {
			remain -= 1
			a.setup_provider_sel = rows[next].provider_idx
		}
	}
}

@(private)
setup_draw_provider_list :: proc(buf: ^ui.Buffer, a: ^App, start_y: int) {
	t := ui.theme()
	rows := setup_provider_rows(a)
	view_h := max(1, buf.height - start_y - 2)
	sel_row := setup_provider_sel_row(rows, a.setup_provider_sel)
	if sel_row < a.setup_scroll {
		a.setup_scroll = sel_row
	}
	if sel_row >= a.setup_scroll + view_h {
		a.setup_scroll = sel_row - view_h + 1
	}
	y := start_y
	for i in a.setup_scroll ..< min(len(rows), a.setup_scroll + view_h) {
		row := rows[i]
		ui.buffer_fill_rect(buf, 0, y, buf.width, 1, ' ', t.fg, t.bg)
		switch row.kind {
		case .Header:
			ui.buffer_text_clip(buf, 1, y, buf.width - 1, row.label, t.muted, t.bg, {.Dim, .Bold})
		case .Item:
			p := a.registry.providers[row.provider_idx]
			mark := " "
			fg := t.fg
			if row.provider_idx == a.setup_provider_sel {
				mark = ">"
				fg = t.accent
			}
			badge := setup_provider_live_badge(a, p.id)
			line := fmt.tprintf("%s %s (%s)%s", mark, p.name, p.id, badge)
			ui.buffer_text_clip(buf, 1, y, buf.width - 1, line, fg, t.bg)
		}
		y += 1
	}
}

@(private)
setup_draw_connection :: proc(buf: ^ui.Buffer, a: ^App, start_y: int) {
	t := ui.theme()
	p := setup_selected_provider(a)
	name := "?"
	if p != nil {
		name = p.id
	}
	ui.buffer_text_clip(buf, 1, start_y, buf.width - 1, fmt.tprintf("provider: %s", name), t.muted, t.bg)
	base_mark := " "
	key_mark := " "
	if a.setup_field == 0 {
		base_mark = ">"
	} else {
		key_mark = ">"
	}
	ui.buffer_text_clip(buf, 1, start_y + 2, buf.width - 1, fmt.tprintf("%s base: %s", base_mark, a.setup_base), t.fg, t.bg)
	if p != nil && setup_provider_needs_key(p.id) {
		shown := a.setup_key
		if p.id != "lmstudio" && len(shown) > 0 {
			shown = setup_mask_key(shown)
			if a.setup_field == 1 {
				shown = a.setup_key
			}
		}
		ui.buffer_text_clip(buf, 1, start_y + 3, buf.width - 1, fmt.tprintf("%s key:  %s", key_mark, shown), t.fg, t.bg)
		ui.buffer_text_clip(buf, 1, start_y + 5, buf.width - 1, "Up/Down field · type to edit · Enter next", t.muted, t.bg, {.Dim})
	} else {
		ui.buffer_text_clip(buf, 1, start_y + 3, buf.width - 1, "no API key required", t.muted, t.bg, {.Dim})
	}
	ui.buffer_text_clip(buf, 1, start_y + 7, buf.width - 1, setup_oauth_note(name), t.muted, t.bg, {.Dim})
}

@(private)
setup_draw_model :: proc(buf: ^ui.Buffer, a: ^App, start_y: int) {
	t := ui.theme()
	ui.buffer_text_clip(buf, 1, start_y, buf.width - 1, fmt.tprintf("model: %s", a.setup_model), t.fg, t.bg)
	ui.buffer_text_clip(buf, 1, start_y + 1, buf.width - 1, fmt.tprintf("filter: %s", a.setup_filter), t.muted, t.bg)
	y := start_y + 3
	view_h := max(1, buf.height - y - 2)
	count := setup_filtered_model_count(a)
	if a.setup_model_sel < a.setup_scroll {
		a.setup_scroll = a.setup_model_sel
	}
	if a.setup_model_sel >= a.setup_scroll + view_h {
		a.setup_scroll = a.setup_model_sel - view_h + 1
	}
	shown := 0
	filt := strings.to_lower(a.setup_filter, context.temp_allocator)
	idx := 0
	for m in a.setup_models {
		if len(filt) > 0 && !strings.contains(strings.to_lower(m.id, context.temp_allocator), filt) {
			continue
		}
		if idx < a.setup_scroll {
			idx += 1
			continue
		}
		if shown >= view_h {
			break
		}
		mark := " "
		fg := t.fg
		if idx == a.setup_model_sel {
			mark = ">"
			fg = t.accent
		}
		ui.buffer_text_clip(buf, 1, y, buf.width - 1, fmt.tprintf("%s %s", mark, m.id), fg, t.bg)
		y += 1
		shown += 1
		idx += 1
	}
	if count == 0 {
		ui.buffer_text_clip(buf, 1, y, buf.width - 1, "type a model id then Enter", t.muted, t.bg, {.Dim})
	}
}

@(private)
setup_draw_reasoning :: proc(buf: ^ui.Buffer, a: ^App, start_y: int) {
	t := ui.theme()
	p := setup_selected_provider(a)
	pid := ""
	if p != nil {
		pid = p.id
	}
	ui.buffer_text_clip(buf, 1, start_y, buf.width - 1, fmt.tprintf("thinking: %s", a.setup_thinking_on ? "on" : "off"), t.fg, t.bg)
	ui.buffer_text_clip(buf, 1, start_y + 1, buf.width - 1, fmt.tprintf("effort: %s", a.setup_effort), t.fg, t.bg)
	ui.buffer_text_clip(buf, 1, start_y + 3, buf.width - 1, "Space toggles thinking · Left/Right effort", t.muted, t.bg, {.Dim})
	if pid == "dashscope" || pid == "cohere" {
		ui.buffer_text_clip(buf, 1, start_y + 4, buf.width - 1, "this provider maps to on/off on the wire", t.muted, t.bg, {.Dim})
	}
	effs := setup_reason_efforts(a)
	line := "levels:"
	for e in effs {
		line = fmt.tprintf("%s %s", line, e)
	}
	ui.buffer_text_clip(buf, 1, start_y + 6, buf.width - 1, line, t.muted, t.bg)
}

@(private)
setup_draw_confirm :: proc(buf: ^ui.Buffer, a: ^App, start_y: int) {
	t := ui.theme()
	p := setup_selected_provider(a)
	pid := "?"
	if p != nil {
		pid = p.id
	}
	ui.buffer_text_clip(buf, 1, start_y, buf.width - 1, fmt.tprintf("provider: %s", pid), t.fg, t.bg)
	ui.buffer_text_clip(buf, 1, start_y + 1, buf.width - 1, fmt.tprintf("base:     %s", a.setup_base), t.fg, t.bg)
	ui.buffer_text_clip(buf, 1, start_y + 2, buf.width - 1, fmt.tprintf("key:      %s", setup_mask_key(a.setup_key)), t.fg, t.bg)
	ui.buffer_text_clip(buf, 1, start_y + 3, buf.width - 1, fmt.tprintf("model:    %s", a.setup_model), t.fg, t.bg)
	ui.buffer_text_clip(buf, 1, start_y + 4, buf.width - 1, fmt.tprintf("reason:   %s", setup_reason_value(a)), t.fg, t.bg)
	ui.buffer_text_clip(buf, 1, start_y + 6, buf.width - 1, "Enter writes ~/.config/nullray/env", t.accent, t.bg)
}
