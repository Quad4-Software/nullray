// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Session task-list tools. The model gets todo_write for full syncs (the
TodoWrite-style "keep this list current" flow), todo_update and todo_add
for small edits, and todo_list to re-read state. Mutation results end with
the compact open-items block so current state is always visible.
*/

package tools

import "core:encoding/json"
import "core:fmt"
import "core:strings"
import "nullray:todo"

@(private)
todo_disabled_err :: proc(allocator := context.allocator) -> string {
	return strings.clone("todo tools disabled (NULLRAY_TODO=0)", allocator)
}

@(private)
todo_readonly_err :: proc(allocator := context.allocator) -> string {
	return strings.clone("todo writes are read-only for subagents; use todo_list", allocator)
}

@(private)
todo_result_with_view :: proc(prefix: string, allocator := context.allocator) -> string {
	view := todo.summary_compact(todo.current_session(), context.temp_allocator)
	if len(view) == 0 {
		view = "(no open tasks)\n"
	}
	return fmt.aprintf("%s\n%s", prefix, view, allocator = allocator)
}

@(private)
json_has_key :: proc(args_json: string, key: string) -> bool {
	doc, perr := json.parse_string(args_json, .JSON, allocator = context.temp_allocator)
	if perr != nil {
		return false
	}
	obj, ok := doc.(json.Object)
	if !ok {
		return false
	}
	_, found := obj[key]
	return found
}

tool_todo_add :: proc(args_json: string, allocator := context.allocator) -> (string, string) {
	if !todo.enabled() {
		return "", todo_disabled_err(allocator)
	}
	if todo.writes_blocked() {
		return "", todo_readonly_err(allocator)
	}
	sid := todo.current_session()
	todo.mark_tool_use(sid)
	text, terr := json_arg_string(args_json, "text", allocator)
	if terr != "" {
		return "", terr
	}
	defer delete(text)
	blocked, berr := json_arg_strings_optional(args_json, "blocked_on", context.temp_allocator)
	if berr != "" {
		return "", strings.clone(berr, allocator)
	}
	id, err := todo.add(sid, text, blocked, allocator)
	if len(err) > 0 {
		return "", err
	}
	defer delete(id)
	return todo_result_with_view(fmt.tprintf("added %s", id), allocator), ""
}

tool_todo_update :: proc(args_json: string, allocator := context.allocator) -> (string, string) {
	if !todo.enabled() {
		return "", todo_disabled_err(allocator)
	}
	if todo.writes_blocked() {
		return "", todo_readonly_err(allocator)
	}
	sid := todo.current_session()
	todo.mark_tool_use(sid)
	id, ierr := json_arg_string(args_json, "id", allocator)
	if ierr != "" {
		return "", ierr
	}
	defer delete(id)
	status, serr := json_arg_string_optional(args_json, "status", "", context.temp_allocator)
	if serr != "" {
		return "", strings.clone(serr, allocator)
	}
	note_set := json_has_key(args_json, "note")
	note, nerr := json_arg_string_optional(args_json, "note", "", context.temp_allocator)
	if nerr != "" {
		return "", strings.clone(nerr, allocator)
	}
	blocked_on_set := json_has_key(args_json, "blocked_on")
	blocked, berr := json_arg_strings_optional(args_json, "blocked_on", context.temp_allocator)
	if berr != "" {
		return "", strings.clone(berr, allocator)
	}
	err := todo.update(sid, id, status, note, note_set, blocked, blocked_on_set, allocator)
	if len(err) > 0 {
		return "", err
	}
	return todo_result_with_view(fmt.tprintf("updated %s", id), allocator), ""
}

@(private)
parse_sync_items :: proc(args_json: string, allocator := context.allocator) -> (items: []todo.Sync_Item, err: string) {
	doc, perr := json.parse_string(args_json, .JSON, allocator = context.temp_allocator)
	if perr != nil {
		return nil, fmt.aprintf("bad tool args JSON: %v", perr, allocator = allocator)
	}
	obj, ok := doc.(json.Object)
	if !ok {
		return nil, strings.clone("tool args must be a JSON object", allocator)
	}
	arr, aok := obj["items"].(json.Array)
	if !aok {
		return nil, strings.clone("missing field: items (array of {id?, text, status?, blocked_on?, note?})", allocator)
	}
	out := make([dynamic]todo.Sync_Item, 0, len(arr), allocator)
	for elem in arr {
		eo, eok := elem.(json.Object)
		if !eok {
			return nil, strings.clone("items[] must be objects", allocator)
		}
		entry: todo.Sync_Item
		if v, found := eo["id"]; found {
			if s, sok := v.(json.String); sok {
				entry.id = string(s)
			}
		}
		if v, found := eo["text"]; found {
			if s, sok := v.(json.String); sok {
				entry.text = string(s)
			}
		}
		if v, found := eo["status"]; found {
			if s, sok := v.(json.String); sok {
				entry.status = string(s)
			}
		}
		if v, found := eo["note"]; found {
			entry.note_set = true
			if s, sok := v.(json.String); sok {
				entry.note = string(s)
			}
		}
		if v, found := eo["blocked_on"]; found {
			entry.blocked_on_set = true
			if barr, bok := v.(json.Array); bok {
				list := make([dynamic]string, 0, len(barr), allocator)
				for belem in barr {
					if s, sok := belem.(json.String); sok {
						append(&list, string(s))
					}
				}
				entry.blocked_on = list[:]
			}
		}
		append(&out, entry)
	}
	return out[:], ""
}

tool_todo_write :: proc(args_json: string, allocator := context.allocator) -> (string, string) {
	if !todo.enabled() {
		return "", todo_disabled_err(allocator)
	}
	if todo.writes_blocked() {
		return "", todo_readonly_err(allocator)
	}
	sid := todo.current_session()
	todo.mark_tool_use(sid)
	items, perr := parse_sync_items(args_json, context.temp_allocator)
	if perr != "" {
		return "", strings.clone(perr, allocator)
	}
	err := todo.sync_items(sid, items, allocator)
	if len(err) > 0 {
		return "", err
	}
	return todo_result_with_view("ok", allocator), ""
}

tool_todo_list :: proc(args_json: string, allocator := context.allocator) -> (string, string) {
	_ = args_json
	if !todo.enabled() {
		return "", todo_disabled_err(allocator)
	}
	sid := todo.current_session()
	todo.mark_tool_use(sid)
	return todo.list_view(sid, allocator), ""
}

register_todo_tools :: proc(r: ^Registry) {
	if r == nil || !todo.enabled() {
		return
	}
	registry_register(r, Tool{
		name = "todo_write",
		description = "Full sync of the session task list. Match by id or exact text; new entries get fresh ids; existing items absent from items are marked cancelled, not deleted. Keep it current as work starts, blocks, and finishes.",
		schema_json = `{"type":"object","properties":{"items":{"type":"array","items":{"type":"object","properties":{"id":{"type":"string"},"text":{"type":"string"},"status":{"type":"string","description":"todo|in_progress|done|blocked|cancelled"},"blocked_on":{"type":"array","items":{"type":"string"},"description":"ids that must finish first"},"note":{"type":"string"}},"required":["text"]}}},"required":["items"]}`,
		kind = .Read,
		run = tool_todo_write,
	})
	registry_register(r, Tool{
		name = "todo_update",
		description = "Update one task: status, note, or blocked_on by id",
		schema_json = `{"type":"object","properties":{"id":{"type":"string"},"status":{"type":"string","description":"todo|in_progress|done|blocked|cancelled"},"note":{"type":"string"},"blocked_on":{"type":"array","items":{"type":"string"}}},"required":["id"]}`,
		kind = .Read,
		run = tool_todo_update,
	})
	registry_register(r, Tool{
		name = "todo_add",
		description = "Add one task to the session task list",
		schema_json = `{"type":"object","properties":{"text":{"type":"string"},"blocked_on":{"type":"array","items":{"type":"string"},"description":"ids that must finish first"}},"required":["text"]}`,
		kind = .Read,
		run = tool_todo_add,
	})
	registry_register(r, Tool{
		name = "todo_list",
		description = "Show the session task list with status markers",
		schema_json = `{"type":"object","properties":{}}`,
		kind = .Read,
		run = tool_todo_list,
	})
}
