// SPDX-License-Identifier: 0BSD
/*
Tool dispatch, mode gating, and OpenAI tools JSON.
*/

package tools

import "core:fmt"
import "core:strings"

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

describe_for_prompt :: proc(r: ^Registry, allocator := context.allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	if r == nil {
		return strings.to_string(b)
	}
	for t, i in r.tools {
		if i > 0 {
			strings.write_string(&b, "\n")
		}
		strings.write_string(&b, t.name)
		strings.write_string(&b, ": ")
		strings.write_string(&b, t.description)
		strings.write_string(&b, " schema=")
		strings.write_string(&b, t.schema_json)
	}
	return strings.to_string(b)
}

openai_tools_json :: proc(r: ^Registry, mode: string, allocator := context.allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	strings.write_string(&b, "[")
	first := true
	if r != nil {
		for t in r.tools {
			if ok, _ := tool_kind_allowed(r, t.name, mode); !ok {
				continue
			}
			if !first {
				strings.write_string(&b, ",")
			}
			first = false
			strings.write_string(&b, `{"type":"function","function":{"name":"`)
			strings.write_string(&b, t.name)
			strings.write_string(&b, `","description":"`)
			strings.write_string(&b, t.description)
			strings.write_string(&b, `","parameters":`)
			strings.write_string(&b, t.schema_json)
			strings.write_string(&b, "}}")
		}
	}
	strings.write_string(&b, "]")
	return strings.to_string(b)
}
