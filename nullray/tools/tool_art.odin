// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
show_art: programmatic figlet / shapes / plots / ANSI blit.
Agents pass a JSON program. Engine rasterizes. No freehand ASCII from the model.
*/

package tools

import "core:fmt"
import "core:strings"
import "nullray:art"

// Optional UI open callback so the TUI can dock the result in the side pane.
Art_Show_Proc :: #type proc(title, body: string, user: rawptr)

@(private)
g_art_show: Art_Show_Proc
@(private)
g_art_show_user: rawptr

register_art_show :: proc(cb: Art_Show_Proc, user: rawptr = nil) {
	g_art_show = cb
	g_art_show_user = user
}

register_art_tools :: proc(r: ^Registry) {
	registry_register(r, Tool{
		name = "show_art",
		description = "Draw terminal art programmatically. Do not freehand ASCII. Pass schema JSON with width/height and ops: figlet, text, rect, line, circle, bars, spark, plot (fn=sin|cos|quad|noise), scatter, ansi. Or pass figlet=\"TEXT\" alone. Returns the raster. Prefer this for banners, charts, boxes.",
		schema_json = `{"type":"object","properties":{"schema":{"type":"string","description":"full art program JSON"},"figlet":{"type":"string","description":"shortcut banner text"},"title":{"type":"string"},"width":{"type":"string"},"height":{"type":"string"},"open":{"type":"string","description":"1 to open side pane"}},"required":[]}`,
		kind = .Read,
		run = tool_show_art,
	})
}

tool_show_art :: proc(args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	schema, _ := json_arg_string_optional(args_json, "schema", "", allocator)
	defer delete(schema)
	src := strings.trim_space(schema)
	if len(src) == 0 {
		// Build from top-level shortcuts
		fig, _ := json_arg_string_optional(args_json, "figlet", "", context.temp_allocator)
		w, _ := json_arg_string_optional(args_json, "width", "64", context.temp_allocator)
		h, _ := json_arg_string_optional(args_json, "height", "20", context.temp_allocator)
		if len(strings.trim_space(fig)) > 0 {
			src = fmt.tprintf(`{"width":%s,"height":%s,"figlet":%q}`, w, h, fig)
		} else {
			// whole args_json as program if it looks like one
			if strings.contains(args_json, `"ops"`) || strings.contains(args_json, `"figlet"`) {
				src = args_json
			}
		}
	}
	if len(strings.trim_space(src)) == 0 {
		return "", strings.clone(`usage: show_art with schema JSON or figlet="TEXT"`, allocator)
	}
	plain, ansi_s, rerr := art.art_render_json(src, allocator)
	if rerr != "" {
		delete(plain)
		delete(ansi_s)
		return "", rerr
	}
	delete(ansi_s) // plain goes to model and pane; ansi reserved for later export
	title, _ := json_arg_string_optional(args_json, "title", "art", context.temp_allocator)
	if len(title) == 0 {
		title = "art"
	}
	open_pane := true
	if o, _ := json_arg_string_optional(args_json, "open", "1", context.temp_allocator); len(o) > 0 {
		switch strings.to_lower(o, context.temp_allocator) {
		case "0", "false", "no", "off":
			open_pane = false
		}
	}
	if open_pane && g_art_show != nil {
		g_art_show(title, plain, g_art_show_user)
	}
	// Cap model-facing body so huge canvases stay cheap.
	out := plain
	if len(out) > 8000 {
		out = strings.clone(fmt.tprintf("%s\n… (%d bytes total)", plain[:8000], len(plain)), allocator)
		delete(plain)
	}
	return out, ""
}
