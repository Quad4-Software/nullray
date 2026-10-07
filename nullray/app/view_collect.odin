// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Collect write paths from the latest user turn for the view pane.
*/

package app

import "core:encoding/json"
import "nullray:provider"
import "nullray:tools"

/*
Collect write paths from the latest user turn (messages after the last user message).
Returned paths are owned by allocator.
*/
collect_turn_write_paths :: proc(messages: []provider.Message, allocator := context.allocator) -> []string {
	start := 0
	for i := len(messages) - 1; i >= 0; i -= 1 {
		if messages[i].role == .User {
			start = i + 1
			break
		}
	}
	out := make([dynamic]string, 0, 8, allocator)
	for i in start ..< len(messages) {
		m := messages[i]
		if m.role != .Assistant {
			continue
		}
		for tc in m.tool_calls {
			extract_write_paths_from_tool(&out, tc.name, tc.arguments, allocator)
		}
	}
	return out[:]
}

@(private)
extract_write_paths_from_tool :: proc(out: ^[dynamic]string, name, args_json: string, allocator := context.allocator) {
	switch name {
	case "write_file", "edit_file":
		path, err := tools.json_arg_string(args_json, "path", context.temp_allocator)
		if err != "" || len(path) == 0 {
			return
		}
		abs := tools.resolve_path(path, allocator)
		append_unique_path(out, abs)
	case "apply_edits":
		extract_apply_edits_paths(out, args_json, allocator)
	}
}

@(private)
append_unique_path :: proc(out: ^[dynamic]string, abs: string) {
	for existing in out {
		if existing == abs {
			delete(abs)
			return
		}
	}
	append(out, abs)
}

@(private)
extract_apply_edits_paths :: proc(out: ^[dynamic]string, args_json: string, allocator := context.allocator) {
	doc, parse_err := json.parse_string(args_json, .JSON, allocator = context.temp_allocator)
	if parse_err != nil {
		return
	}
	obj, ok := doc.(json.Object)
	if !ok {
		return
	}
	for key in ([]string{"edits", "files"}) {
		val, found := obj[key]
		if !found {
			continue
		}
		arr, aok := val.(json.Array)
		if !aok {
			continue
		}
		for item in arr {
			item_obj, iok := item.(json.Object)
			if !iok {
				continue
			}
			pv, pf := item_obj["path"]
			if !pf {
				continue
			}
			ps, pok := pv.(json.String)
			if !pok || len(string(ps)) == 0 {
				continue
			}
			abs := tools.resolve_path(string(ps), allocator)
			append_unique_path(out, abs)
		}
	}
}

destroy_write_paths :: proc(paths: []string, allocator := context.allocator) {
	for p in paths {
		delete(p, allocator)
	}
	delete(paths, allocator)
}
