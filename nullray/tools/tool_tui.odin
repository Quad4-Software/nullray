// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
set_tui: agent-driven session or global TUI theme customization.
*/

package tools

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"
import "nullray:constants"
import "nullray:ui"

// Callback so the App can refresh the live loop theme after set_tui.
Tui_Apply_Proc :: #type proc(theme: ui.Theme, persistent: bool, user: rawptr)

@(private)
g_tui_apply: Tui_Apply_Proc
@(private)
g_tui_apply_user: rawptr

register_tui_apply :: proc(cb: Tui_Apply_Proc, user: rawptr = nil) {
	g_tui_apply = cb
	g_tui_apply_user = user
}

ui_malleable_enabled :: proc() -> bool {
	if v, ok := os.lookup_env(constants.ENV_UI_MALLEABLE, context.temp_allocator); ok {
		switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
		case "0", "false", "off", "no", "disable", "disabled":
			return false
		}
	}
	return true
}

ui_global_locked :: proc() -> bool {
	if v, ok := os.lookup_env(constants.ENV_UI_LOCK, context.temp_allocator); ok {
		switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
		case "1", "true", "on", "yes", "lock", "locked":
			return true
		}
	}
	return false
}

register_tui_tools :: proc(r: ^Registry) {
	registry_register(r, Tool{
		name = "set_tui",
		description = "Customize the nullray TUI theme for this session or globally. Pass theme=ink|ember|... or colors map (bg,fg,accent,title,... as #rrggbb or names). scope=session (default) or global. action=get|set|reset. Disabled when NULLRAY_UI_MALLEABLE=0. Global writes blocked when NULLRAY_UI_LOCK=1.",
		schema_json = `{"type":"object","properties":{"action":{"type":"string","description":"get|set|reset"},"scope":{"type":"string","description":"session|global"},"theme":{"type":"string","description":"base theme name"},"colors":{"type":"object","description":"slot to color hex/name"},"schema":{"type":"string","description":"full theme JSON"}},"required":[]}`,
		kind = .Read,
		run = tool_set_tui,
	})
}

tool_set_tui :: proc(args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	if !ui_malleable_enabled() {
		return "", strings.clone("set_tui disabled (NULLRAY_UI_MALLEABLE=0)", allocator)
	}
	action, _ := json_arg_string_optional(args_json, "action", "set", allocator)
	defer delete(action)
	act := strings.to_lower(strings.trim_space(action), context.temp_allocator)
	if act == "get" || act == "show" || act == "status" {
		cur := ui.theme()
		js := ui.theme_export_json(cur, allocator)
		return js, ""
	}
	if act == "reset" || act == "default" || act == "clear" {
		os.set_env(constants.ENV_UI_RESET, "1")
		_ = ui.theme_clear_custom()
		base := "ink"
		if v, ok := os.lookup_env(constants.ENV_THEME, context.temp_allocator); ok && len(v) > 0 {
			base = v
		}
		t := ui.theme_by_name(base)
		ui.theme_set(t)
		if g_tui_apply != nil {
			g_tui_apply(t, true, g_tui_apply_user)
		}
		return strings.clone("{\"ok\":true,\"action\":\"reset\",\"theme\":\"restored\"}", allocator), ""
	}

	scope, _ := json_arg_string_optional(args_json, "scope", "session", allocator)
	defer delete(scope)
	persistent := strings.to_lower(strings.trim_space(scope), context.temp_allocator) == "global"
	if persistent && ui_global_locked() {
		return "", strings.clone("global TUI lock on (NULLRAY_UI_LOCK=1); use scope=session", allocator)
	}

	schema, _ := json_arg_string_optional(args_json, "schema", "", allocator)
	defer delete(schema)
	t: ui.Theme
	if len(strings.trim_space(schema)) > 0 {
		pt, perr := ui.theme_from_json(schema)
		if perr != "" {
			return "", strings.clone(perr, allocator)
		}
		t = pt
	} else {
		theme_name, _ := json_arg_string_optional(args_json, "theme", "", context.temp_allocator)
		base := ui.theme()
		if len(theme_name) > 0 {
			if theme_name != "custom" && !ui.theme_exists(theme_name) {
				return "", fmt.aprintf("unknown theme %s", theme_name, allocator = allocator)
			}
			if theme_name != "custom" {
				base = ui.theme_by_name(theme_name)
			}
		}
		colors := make(map[string]string, context.temp_allocator)
		if m, merr := json_arg_string_map(args_json, "colors"); merr == "" {
			for k, v in m {
				colors[k] = v
			}
		}
		slots := []string{
			"bg", "fg", "muted", "border", "accent", "accent_dim", "title", "warn", "ok", "error",
			"status_bg", "status_fg", "input_bg", "code_bg", "code_fg", "link_fg", "heading_fg", "bold_fg",
		}
		for slot in slots {
			if v, verr := json_arg_string_optional(args_json, slot, "", context.temp_allocator); verr == "" && len(v) > 0 {
				colors[slot] = v
			}
		}
		t = ui.theme_apply_colors(base, colors)
	}

	ui.theme_set(t)
	if persistent {
		js := ui.theme_export_json(t, context.temp_allocator)
		ok, werr := ui.theme_save_custom(js)
		if !ok {
			return "", strings.clone(werr, allocator)
		}
	}
	if g_tui_apply != nil {
		g_tui_apply(t, persistent, g_tui_apply_user)
	}
	scope_s := persistent ? "global" : "session"
	// Avoid fmt treating { as a format directive: build JSON by hand.
	b: strings.Builder
	strings.builder_init(&b, allocator)
	strings.write_string(&b, `{"ok":true,"scope":"`)
	strings.write_string(&b, scope_s)
	strings.write_string(&b, `","theme":"`)
	strings.write_string(&b, t.name)
	strings.write_string(&b, `"}`)
	return strings.to_string(b), ""
}

@(private)
json_arg_string_map :: proc(args_json, key: string) -> (map[string]string, string) {
	out := make(map[string]string, context.temp_allocator)
	doc, perr := json.parse_string(args_json, .JSON, allocator = context.temp_allocator)
	if perr != .None {
		return out, "bad json"
	}
	obj, ok := doc.(json.Object)
	if !ok {
		return out, "not object"
	}
	v, has := obj[key]
	if !has {
		return out, "missing"
	}
	co, cok := v.(json.Object)
	if !cok {
		return out, "not object"
	}
	for k, val in co {
		if s, sok := val.(json.String); sok {
			out[k] = string(s)
		}
	}
	return out, ""
}
