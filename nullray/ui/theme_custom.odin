// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Agent/user custom theme overlays: parse color maps onto a base Theme and
optional persistence under the config dir.
*/

package ui

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "nullray:constants"

CUSTOM_THEME_FILE :: "theme_custom.json"

// Apply a flat map of slot -> color string onto base. Unknown slots ignored.
// slots: bg, fg, muted, border, accent, accent_dim, highlight_bg, highlight_fg,
// warn, ok, error, title, status_bg, status_fg, input_bg, user_fg, user_bg,
// assistant_fg, code_bg, code_fg, link_fg, quote_fg, table_fg, heading_fg, bold_fg
theme_apply_colors :: proc(base: Theme, colors: map[string]string) -> Theme {
	t := base
	if len(base.name) == 0 || base.name == "ink" || base.name == "ember" || base.name == "moss" ||
		base.name == "slate" || base.name == "rose" || base.name == "mono" || base.name == "dusk" {
		// mark as custom overlay name when any override lands
	}
	changed := false
	for k, v in colors {
		c, ok := color_parse(v)
		if !ok {
			continue
		}
		if theme_set_slot(&t, k, c) {
			changed = true
		}
	}
	if changed {
		t.name = "custom"
	}
	return t
}

theme_set_slot :: proc(t: ^Theme, slot: string, c: Color) -> bool {
	key := strings.to_lower(strings.trim_space(slot), context.temp_allocator)
	switch key {
	case "bg", "background":
		t.bg = c
	case "fg", "foreground", "text":
		t.fg = c
	case "muted", "dim":
		t.muted = c
	case "border":
		t.border = c
	case "accent":
		t.accent = c
	case "accent_dim", "accent-dim":
		t.accent_dim = c
	case "highlight_bg", "highlight-bg", "sel_bg":
		t.highlight_bg = c
	case "highlight_fg", "highlight-fg", "sel_fg":
		t.highlight_fg = c
	case "warn", "warning":
		t.warn = c
	case "ok", "success":
		t.ok = c
	case "error", "err", "danger":
		t.error = c
	case "title", "brand":
		t.title = c
	case "status_bg", "status-bg":
		t.status_bg = c
	case "status_fg", "status-fg":
		t.status_fg = c
	case "input_bg", "input-bg":
		t.input_bg = c
	case "user_fg", "user-fg":
		t.user_fg = c
	case "user_bg", "user-bg":
		t.user_bg = c
	case "assistant_fg", "assistant-fg":
		t.assistant_fg = c
	case "code_bg", "code-bg":
		t.code_bg = c
	case "code_fg", "code-fg":
		t.code_fg = c
	case "link_fg", "link-fg", "link":
		t.link_fg = c
	case "quote_fg", "quote-fg", "quote":
		t.quote_fg = c
	case "table_fg", "table-fg", "table":
		t.table_fg = c
	case "heading_fg", "heading-fg", "heading":
		t.heading_fg = c
	case "bold_fg", "bold-fg", "bold":
		t.bold_fg = c
	case:
		return false
	}
	return true
}

// JSON object of slot->color, optional base theme name.
theme_from_json :: proc(raw: string, allocator := context.allocator) -> (Theme, string) {
	_ = allocator
	doc, perr := json.parse_string(raw, .JSON, allocator = context.temp_allocator)
	if perr != .None {
		return {}, "theme json invalid"
	}
	obj, ok := doc.(json.Object)
	if !ok {
		return {}, "theme root must be object"
	}
	base_name := "ink"
	if v, has := obj["base"]; has {
		if s, sok := v.(json.String); sok && len(string(s)) > 0 {
			base_name = string(s)
		}
	}
	if v, has := obj["theme"]; has {
		if s, sok := v.(json.String); sok && len(string(s)) > 0 {
			base_name = string(s)
		}
	}
	base := theme_by_name(base_name)
	colors := make(map[string]string, context.temp_allocator)
	if cv, has := obj["colors"]; has {
		if co, cok := cv.(json.Object); cok {
			for k, val in co {
				if s, sok := val.(json.String); sok {
					colors[k] = string(s)
				}
			}
		}
	} else {
		// Allow top-level slots directly.
		for k, val in obj {
			if k == "base" || k == "theme" || k == "name" {
				continue
			}
			if s, sok := val.(json.String); sok {
				colors[k] = string(s)
			}
		}
	}
	t := theme_apply_colors(base, colors)
	if v, has := obj["name"]; has {
		if s, sok := v.(json.String); sok && len(string(s)) > 0 {
			t.name = string(s)
		}
	}
	return t, ""
}

theme_custom_path :: proc(allocator := context.allocator) -> string {
	dir := "."
	if xdg, ok := os.lookup_env("XDG_CONFIG_HOME", context.temp_allocator); ok && len(xdg) > 0 {
		if joined, jerr := filepath.join({xdg, constants.CONFIG_DIR_NAME}, context.temp_allocator); jerr == nil {
			dir = joined
		}
	} else if home, ok := os.lookup_env("HOME", context.temp_allocator); ok {
		if joined, jerr := filepath.join({home, ".config", constants.CONFIG_DIR_NAME}, context.temp_allocator); jerr == nil {
			dir = joined
		}
	}
	p, err := filepath.join({dir, CUSTOM_THEME_FILE}, allocator)
	if err != nil {
		return strings.concatenate({dir, "/", CUSTOM_THEME_FILE}, allocator)
	}
	return p
}

theme_save_custom :: proc(raw_json: string) -> (ok: bool, err: string) {
	path := theme_custom_path(context.temp_allocator)
	dir := filepath.dir(path)
	_ = os.make_directory_all(dir)
	if os.write_entire_file(path, transmute([]u8)raw_json) != nil {
		return false, "failed to write theme_custom.json"
	}
	return true, ""
}

theme_load_custom :: proc() -> (Theme, bool) {
	path := theme_custom_path(context.temp_allocator)
	data, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil || len(data) == 0 {
		return {}, false
	}
	t, perr := theme_from_json(string(data))
	if perr != "" {
		return {}, false
	}
	return t, true
}

theme_clear_custom :: proc() -> bool {
	path := theme_custom_path(context.temp_allocator)
	_ = os.remove(path)
	return true
}

// Snapshot of current theme slots for agent feedback.
theme_export_json :: proc(t: Theme, allocator := context.allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	fmt.sbprintf(&b, `{"name":%q,"base":"custom","colors":{`, t.name)
	pairs := []struct {
		k: string,
		c: Color,
	}{
		{"bg", t.bg},
		{"fg", t.fg},
		{"muted", t.muted},
		{"border", t.border},
		{"accent", t.accent},
		{"accent_dim", t.accent_dim},
		{"highlight_bg", t.highlight_bg},
		{"highlight_fg", t.highlight_fg},
		{"warn", t.warn},
		{"ok", t.ok},
		{"error", t.error},
		{"title", t.title},
		{"status_bg", t.status_bg},
		{"status_fg", t.status_fg},
		{"input_bg", t.input_bg},
		{"user_fg", t.user_fg},
		{"user_bg", t.user_bg},
		{"assistant_fg", t.assistant_fg},
		{"code_bg", t.code_bg},
		{"code_fg", t.code_fg},
		{"link_fg", t.link_fg},
		{"quote_fg", t.quote_fg},
		{"table_fg", t.table_fg},
		{"heading_fg", t.heading_fg},
		{"bold_fg", t.bold_fg},
	}
	for p, i in pairs {
		if i > 0 {
			strings.write_byte(&b, ',')
		}
		fmt.sbprintf(&b, `%q:"#%02x%02x%02x"`, p.k, p.c.r, p.c.g, p.c.b)
	}
	strings.write_string(&b, `}}`)
	return strings.to_string(b)
}
