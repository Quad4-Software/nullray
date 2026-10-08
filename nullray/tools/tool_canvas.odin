// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
canvas_list / canvas_save / canvas_open tools for durable agent panel UIs.
*/

package tools

import "core:fmt"
import "core:strings"
import "nullray:store"

tool_canvas_list :: proc(args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	_ = args_json
	return store.canvas_list_text(allocator), ""
}

tool_canvas_save :: proc(args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	schema, _ := json_arg_string_optional(args_json, "schema", "", allocator)
	defer delete(schema)
	if len(strings.trim_space(schema)) == 0 {
		return "", strings.clone("schema required (show_view JSON object)", allocator)
	}
	id, _ := json_arg_string_optional(args_json, "id", "", allocator)
	defer delete(id)
	title, _ := json_arg_string_optional(args_json, "title", "", allocator)
	defer delete(title)
	sid, serr := store.canvas_save(id, title, schema, allocator)
	if serr != "" {
		return "", serr
	}
	out := fmt.aprintf("canvas saved id=%s (reopen with canvas_open or /canvas open %s)", sid, sid, allocator = allocator)
	delete(sid)
	return out, ""
}

tool_canvas_open :: proc(args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	id, perr := json_arg_string(args_json, "id", allocator)
	if perr != "" {
		return "", perr
	}
	defer delete(id)
	schema, title, lerr := store.canvas_load(id, allocator)
	if lerr != "" {
		return "", lerr
	}
	defer delete(schema)
	defer delete(title)
	// Return schema so the agent or UI can re-open via show_view.
	return fmt.aprintf("canvas id=%s title=%s\nRe-open with show_view using this schema:\n%s", id, title, schema, allocator = allocator), ""
}

register_canvas_tools :: proc(r: ^Registry) {
	registry_register(r, Tool{
		name = "canvas_list",
		description = "List saved agent canvas apps (panel UIs) under the config canvases dir",
		schema_json = `{"type":"object","properties":{}}`,
		kind = .Read,
		run = tool_canvas_list,
	})
	registry_register(r, Tool{
		name = "canvas_save",
		description = "Persist a show_view schema as a named canvas app for later reopen. Pass schema JSON and optional id/title.",
		schema_json = `{"type":"object","properties":{"id":{"type":"string"},"title":{"type":"string"},"schema":{"type":"string"}},"required":["schema"]}`,
		kind = .Write,
		run = tool_canvas_save,
	})
	registry_register(r, Tool{
		name = "canvas_open",
		description = "Load a saved canvas schema by id (returns schema text for show_view)",
		schema_json = `{"type":"object","properties":{"id":{"type":"string"}},"required":["id"]}`,
		kind = .Read,
		run = tool_canvas_open,
	})
}
