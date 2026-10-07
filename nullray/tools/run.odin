// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Tool dispatch, mode gating, and OpenAI tools JSON.
*/

package tools

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"
import "nullray:constants"
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
	"models_list",
	"model_use",
	"board_list",
	"board_add",
	"board_claim",
	"board_done",
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
	case "read_file", "write_file", "edit_file", "apply_edits", "list_dir", "repo_map",
		"grep_files", "glob_files", "run_shell", "run_script",
		"load_skill", "list_skills", "compact_context", "search_tools",
		"read_artifact", "grep_artifact",
		"memory_get", "memory_put", "memory_list", "memory_delete", "memory_forget", "memory_search",
		"rag_status", "rag_query", "rag_reindex",
		"read_man", "apropos", "read_tldr", "read_info", "read_help", "lang_doc", "fetch_url", "web_search",
		"list_scaffolds", "scaffold", "audit_structure",
		"vcs_status", "vcs_diff", "vcs_log", "vcs_commit", "vcs_branch", "vcs_merge",
		"vcs_rebase", "vcs_push", "vcs_pull", "vcs_fetch",
		"vcs_pr_create", "vcs_pr_view", "vcs_pr_checks", "vcs_pr_watch",
		"todo_write", "todo_update", "todo_add", "todo_list",
		"schedule_prompt", "schedule_list", "schedule_cancel",
		"harness_list", "harness_run":
		return true
	}
	return false
}

/*
Audit scanners for lean when NULLRAY_HUNT is on. Keeps review hunt from
instructing audit_* while tools_json omits them.
*/
lean_hunt_tool :: proc(name: string) -> bool {
	switch name {
	case "audit_owasp", "audit_deps", "audit_dockerfile", "audit_compose", "audit_actions":
		return true
	}
	return false
}

lean_hunt_tools_enabled :: proc() -> bool {
	if v, ok := os.lookup_env(constants.ENV_HUNT, context.temp_allocator); ok {
		raw := strings.to_lower(strings.trim_space(v), context.temp_allocator)
		switch raw {
		case "", "0", "false", "no", "off", "disable", "disabled":
			return false
		}
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
		"knowledge_get", "knowledge_put", "knowledge_list", "models_list",
		"todo_list":
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
	b := strings.builder_make(allocator)
	json_emit_sorted(stripped, &b)
	return strings.to_string(b)
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
When allow is non-empty, only those tool names pass (after mode checks).
*/
tool_name_in_allow :: proc(name: string, allow: []string) -> bool {
	if len(allow) == 0 {
		return true
	}
	for a in allow {
		if a == name {
			return true
		}
	}
	return false
}

LOCATE_TOOL_ALLOW :: []string{"repo_map", "glob_files", "grep_files", "read_file", "list_dir"}
ARCHITECT_TOOL_ALLOW :: []string{
	"repo_map",
	"glob_files",
	"grep_files",
	"read_file",
	"list_dir",
	"list_scaffolds",
}

tool_kind_allowed :: proc(
	r: ^Registry,
	name: string,
	mode: string,
	allow: []string = nil,
) -> (ok: bool, reason: string) {
	if !tool_name_in_allow(name, allow) {
		return false, "tool not in allowlist for this agent"
	}
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

run :: proc(
	r: ^Registry,
	name: string,
	args_json: string,
	mode: string,
	allocator := context.allocator,
	allow: []string = nil,
) -> (result: string, err: string) {
	if ok, reason := tool_kind_allowed(r, name, mode, allow); !ok {
		return "", strings.clone(reason, allocator)
	}
	if ok, reason := gate_allows_tool(r, name); !ok {
		return "", strings.clone(reason, allocator)
	}
	if strings.has_prefix(name, "mcp:") && r != nil && r.external_run != nil {
		return r.external_run(r.external_user, name, args_json, allocator)
	}
	// Weak models emit name variants (read-file, readfile, default_api.read_file),
	// normalize before rejecting.
	resolved := name
	if _, ok := registry_find(r, resolved); !ok {
		norm := normalize_tool_name(name, context.temp_allocator)
		if norm != resolved {
			if _, ok2 := registry_find(r, norm); ok2 {
				resolved = norm
			}
		}
	}
	t, ok := registry_find(r, resolved)
	if !ok {
		if near := closest_tool_name(r, name, context.temp_allocator); len(near) > 0 {
			return "", fmt.aprintf("unknown tool: %s (did you mean %s?)", name, near, allocator = allocator)
		}
		return "", fmt.aprintf("unknown tool: %s", name, allocator = allocator)
	}
	if t.run_named != nil {
		return t.run_named(t.user, resolved, args_json, allocator)
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
describe_for_prompt :: proc(
	r: ^Registry,
	allocator := context.allocator,
	mode := "",
	allow: []string = nil,
) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	if r == nil {
		return strings.to_string(b)
	}
	first := true
	for t in r.tools {
		if len(mode) > 0 {
			if ok, _ := tool_kind_allowed(r, t.name, mode, allow); !ok {
				continue
			}
		} else if !tool_name_in_allow(t.name, allow) {
			continue
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

// provider_id gates schema hygiene: llamacpp and ollama (or
// NULLRAY_SCHEMA_CLEAN=1) get constraint keywords stripped per schema.
openai_tools_json :: proc(
	r: ^Registry,
	mode: string,
	tier := Prompt_Tier.Full,
	allocator := context.allocator,
	allow: []string = nil,
	provider_id := "",
) -> string {
	clean := schema_clean_enabled(provider_id)
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
			if tier == .Tiny {
				if !tiny_core_tool(t.name) && !deferred_active(t.name) {
					continue
				}
			} else if tier == .Lean {
				// run_named marks a registered user script tool, scripts are
				// trusted at registration so they stay visible in lean too.
				core := lean_core_tool(t.name) || t.run_named != nil
				sub := sub_on && lean_subagent_tool(t.name)
				hunt := lean_hunt_tools_enabled() && lean_hunt_tool(t.name)
				deferred := deferred_active(t.name)
				if !core && !sub && !hunt && !deferred {
					continue
				}
			}
			if ok, _ := tool_kind_allowed(r, t.name, mode, allow); !ok {
				continue
			}
			if !first {
				strings.write_string(&b, ",")
			}
			first = false
			desc := t.description
			if tier != .Full {
				desc = ""
			}
			esc := json_escape_string(desc, context.temp_allocator)
			schema := t.schema_json
			if clean {
				schema = schema_sanitize(schema, context.temp_allocator)
			}
			if tier != .Full {
				schema = schema_strip_descriptions(schema, context.temp_allocator)
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
