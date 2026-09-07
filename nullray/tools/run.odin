/*
Tool dispatch, mode gating, and OpenAI tools JSON.
*/

package tools

import "core:fmt"
import "core:os"
import "core:strings"
import "nullray:constants"

WRITE_TOOLS :: []string{"write_file", "edit_file", "apply_edits"}
SHELL_TOOLS :: []string{"run_shell", "run_script"}

/*
Ask and plan modes (NULLRAY_MODE) are read-only. Edit allows write and shell.
*/
tool_kind_allowed :: proc(name: string) -> (ok: bool, reason: string) {
	mode := "edit"
	if v, vok := os.lookup_env(constants.ENV_MODE, context.temp_allocator); vok && len(v) > 0 {
		mode = strings.to_lower(strings.trim_space(v), context.temp_allocator)
	}
	allow_write := mode == "edit"
	allow_shell := mode == "edit"
	for w in WRITE_TOOLS {
		if name == w {
			if !allow_write {
				return false, "tool blocked in ask/plan mode (switch with /mode edit)"
			}
			return true, ""
		}
	}
	for s in SHELL_TOOLS {
		if name == s {
			if !allow_shell {
				return false, "shell blocked in ask/plan mode (switch with /mode edit)"
			}
			return true, ""
		}
	}
	if strings.has_prefix(name, "mcp:") && !allow_write {
		return false, "mcp tools blocked in ask/plan mode"
	}
	return true, ""
}

run :: proc(name: string, args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	if ok, reason := tool_kind_allowed(name); !ok {
		return "", strings.clone(reason, allocator)
	}
	if strings.has_prefix(name, "mcp:") && g_external_run != nil {
		return g_external_run(name, args_json, allocator)
	}
	t, ok := find(name)
	if !ok {
		return "", fmt.aprintf("unknown tool: %s", name, allocator = allocator)
	}
	if t.run == nil {
		return "", fmt.aprintf("tool not runnable: %s", name, allocator = allocator)
	}
	return t.run(args_json, allocator)
}

describe_for_prompt :: proc(allocator := context.allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	for t, i in g_registry.tools {
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

openai_tools_json :: proc(allocator := context.allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	strings.write_string(&b, "[")
	first := true
	for t in g_registry.tools {
		if ok, _ := tool_kind_allowed(t.name); !ok {
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
	strings.write_string(&b, "]")
	return strings.to_string(b)
}


