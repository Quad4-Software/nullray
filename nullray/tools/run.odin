// SPDX-License-Identifier: 0BSD
/*
Tool dispatch, mode gating, and OpenAI tools JSON.
*/

package tools

import "core:encoding/json"
import "core:fmt"
import "core:strings"
import "nullray:subagent"

subagent_runtime_enabled :: proc() -> bool {
	rt := subagent.runtime()
	if rt == nil {
		return false
	}
	return subagent.runtime_enabled(rt)
}

SUBAGENT_TOOL_NAMES :: []string{
	"task",
	"agents_status",
	"agents_peek",
	"agents_progress",
	"agents_wait",
	"agents_verify",
	"knowledge_get",
	"knowledge_put",
	"knowledge_list",
	"model_use",
	"board_list",
	"board_add",
	"board_claim",
	"send_message",
	"read_messages",
}

is_subagent_tool_name :: proc(name: string) -> bool {
	for n in SUBAGENT_TOOL_NAMES {
		if n == name {
			return true
		}
	}
	return false
}

lean_core_tool :: proc(name: string) -> bool {
	switch name {
	case "read_file", "write_file", "edit_file", "apply_edits", "list_dir",
		"grep_files", "glob_files", "run_shell", "run_script",
		"load_skill", "list_skills", "compact_context",
		"read_artifact", "grep_artifact",
		"memory_get", "memory_put", "memory_list",
		"read_man", "apropos":
		return true
	}
	return false
}

/*
Lean print keeps a small coordination subset when subagents are enabled.
Board/messaging stay out to protect tools-JSON size.
*/
lean_subagent_tool :: proc(name: string) -> bool {
	switch name {
	case "task", "agents_status", "agents_peek", "agents_progress",
		"agents_wait", "agents_verify",
		"knowledge_get", "knowledge_put", "knowledge_list":
		return true
	}
	return false
}

json_escape_string :: proc(s: string, allocator := context.allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	for r in s {
		switch r {
		case '"':
			strings.write_string(&b, `\"`)
		case '\\':
			strings.write_string(&b, `\\`)
		case '\b':
			strings.write_string(&b, `\b`)
		case '\f':
			strings.write_string(&b, `\f`)
		case '\n':
			strings.write_string(&b, `\n`)
		case '\r':
			strings.write_string(&b, `\r`)
		case '\t':
			strings.write_string(&b, `\t`)
		case:
			if r < 0x20 {
				fmt.sbprintf(&b, `\u%04x`, int(r))
			} else {
				strings.write_rune(&b, r)
			}
		}
	}
	return strings.to_string(b)
}

schema_strip_descriptions :: proc(schema: string, allocator := context.allocator) -> string {
	doc, perr := json.parse_string(schema, .JSON, allocator = context.temp_allocator)
	if perr != nil {
		return strings.clone(schema, allocator)
	}
	stripped := schema_strip_descriptions_clone(doc, context.temp_allocator)
	out, uerr := json.unparse(stripped, allocator = allocator)
	if uerr != nil {
		return strings.clone(schema, allocator)
	}
	return out
}

schema_strip_descriptions_clone :: proc(v: json.Value, allocator := context.allocator) -> json.Value {
	#partial switch val in v {
	case json.Object:
		out: json.Object
		out = make(json.Object, allocator = allocator)
		for k, child in val {
			if k == "description" {
				continue
			}
			out[strings.clone(k, allocator)] = schema_strip_descriptions_clone(child, allocator)
		}
		return out
	case json.Array:
		out := make(json.Array, 0, len(val), allocator)
		for item in val {
			append(&out, schema_strip_descriptions_clone(item, allocator))
		}
		return out
	case json.String:
		return strings.clone(val, allocator)
	}
	return v
}

/*
Ask, plan, and review modes are read-only. Edit allows write and shell.
mode is ask|plan|review|edit (case-insensitive). Unknown modes treat as edit.
*/
tool_kind_allowed :: proc(r: ^Registry, name: string, mode: string) -> (ok: bool, reason: string) {
	m := strings.to_lower(strings.trim_space(mode), context.temp_allocator)
	allow_write := m == "edit" || m == ""
	allow_shell := allow_write

	t, found := registry_find(r, name)
	kind := Tool_Kind.Read
	if found {
		kind = t.kind
	} else if strings.has_prefix(name, "mcp:") {
		kind = .Mcp
	} else {
		return true, ""
	}

	switch kind {
	case .Write:
		if !allow_write {
			return false, "tool blocked in ask/plan/review mode (switch with /mode edit)"
		}
	case .Shell:
		if !allow_shell {
			return false, "shell blocked in ask/plan/review mode (switch with /mode edit)"
		}
	case .Mcp:
		if !allow_write {
			return false, "mcp tools blocked in ask/plan/review mode"
		}
	case .Read:
	}
	return true, ""
}

run :: proc(r: ^Registry, name: string, args_json: string, mode: string, allocator := context.allocator) -> (result: string, err: string) {
	if ok, reason := tool_kind_allowed(r, name, mode); !ok {
		return "", strings.clone(reason, allocator)
	}
	if strings.has_prefix(name, "mcp:") && r != nil && r.external_run != nil {
		return r.external_run(r.external_user, name, args_json, allocator)
	}
	t, ok := registry_find(r, name)
	if !ok {
		return "", fmt.aprintf("unknown tool: %s", name, allocator = allocator)
	}
	if t.run == nil {
		return "", fmt.aprintf("tool not runnable: %s", name, allocator = allocator)
	}
	return t.run(args_json, allocator)
}

/*
Names and one-line descriptions only. Full JSON schemas go in the API tools array.
When mode is non-empty, skip tools blocked for that mode.
*/
describe_for_prompt :: proc(r: ^Registry, allocator := context.allocator, mode := "") -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	if r == nil {
		return strings.to_string(b)
	}
	first := true
	for t in r.tools {
		if len(mode) > 0 {
			if ok, _ := tool_kind_allowed(r, t.name, mode); !ok {
				continue
			}
		}
		if !first {
			strings.write_string(&b, "\n")
		}
		first = false
		strings.write_string(&b, t.name)
		strings.write_string(&b, ": ")
		strings.write_string(&b, t.description)
	}
	return strings.to_string(b)
}

openai_tools_json :: proc(r: ^Registry, mode: string, lean := false, allocator := context.allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	strings.write_string(&b, "[")
	first := true
	sub_on := subagent_runtime_enabled()
	if r != nil {
		for t in r.tools {
			if !sub_on && is_subagent_tool_name(t.name) {
				continue
			}
			if lean {
				core := lean_core_tool(t.name)
				sub := sub_on && lean_subagent_tool(t.name)
				if !core && !sub {
					continue
				}
			}
			if ok, _ := tool_kind_allowed(r, t.name, mode); !ok {
				continue
			}
			if !first {
				strings.write_string(&b, ",")
			}
			first = false
			desc := t.description
			if lean {
				desc = ""
			}
			esc := json_escape_string(desc, context.temp_allocator)
			schema := t.schema_json
			if lean {
				schema = schema_strip_descriptions(t.schema_json, context.temp_allocator)
			}
			strings.write_string(&b, `{"type":"function","function":{"name":"`)
			strings.write_string(&b, t.name)
			strings.write_string(&b, `","description":"`)
			strings.write_string(&b, esc)
			strings.write_string(&b, `","parameters":`)
			strings.write_string(&b, schema)
			strings.write_string(&b, "}}")
		}
	}
	strings.write_string(&b, "]")
	return strings.to_string(b)
}
