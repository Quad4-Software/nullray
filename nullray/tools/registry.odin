// SPDX-License-Identifier: 0BSD
/*
Tool registry: registration, lookup, and init of built-ins.
*/

package tools

Tool_Kind :: enum {
	Read,
	Write,
	Shell,
	Mcp,
}

Tool_Proc :: #type proc(args_json: string, allocator := context.allocator) -> (result: string, err: string)

External_Run_Proc :: #type proc(
	user: rawptr,
	name: string,
	args_json: string,
	allocator := context.allocator,
) -> (result: string, err: string)

Tool :: struct {
	name:        string,
	description: string,
	schema_json: string,
	kind:        Tool_Kind,
	run:         Tool_Proc,
}

Registry :: struct {
	tools:          [dynamic]Tool,
	external_run:   External_Run_Proc,
	external_user:  rawptr,
}

g_registry: Registry

registry :: proc() -> ^Registry {
	return &g_registry
}

registry_init :: proc(r: ^Registry) {
	r^ = {}
	r.tools = make([dynamic]Tool)
	registry_register(r, Tool{
		name = "read_file",
		description = "Read a UTF-8 text file under the workspace",
		schema_json = `{"type":"object","properties":{"path":{"type":"string"}},"required":["path"]}`,
		kind = .Read,
		run = tool_read_file,
	})
	registry_register(r, Tool{
		name = "write_file",
		description = "Write UTF-8 text to a file under the workspace",
		schema_json = `{"type":"object","properties":{"path":{"type":"string"},"content":{"type":"string"}},"required":["path","content"]}`,
		kind = .Write,
		run = tool_write_file,
	})
	registry_register(r, Tool{
		name = "list_dir",
		description = "List entries in a directory under the workspace",
		schema_json = `{"type":"object","properties":{"path":{"type":"string"}},"required":["path"]}`,
		kind = .Read,
		run = tool_list_dir,
	})
	registry_register(r, Tool{
		name = "edit_file",
		description = "Replace text in a UTF-8 file under the workspace",
		schema_json = `{"type":"object","properties":{"path":{"type":"string"},"old_string":{"type":"string"},"new_string":{"type":"string"},"replace_all":{"type":"string","description":"true or false"}},"required":["path","old_string","new_string"]}`,
		kind = .Write,
		run = tool_edit_file,
	})
	registry_register(r, Tool{
		name = "grep_files",
		description = "Search for a substring in files under the workspace",
		schema_json = `{"type":"object","properties":{"pattern":{"type":"string"},"path":{"type":"string"},"glob":{"type":"string"}},"required":["pattern"]}`,
		kind = .Read,
		run = tool_grep_files,
	})
	registry_register(r, Tool{
		name = "glob_files",
		description = "List files matching a glob pattern under the workspace",
		schema_json = `{"type":"object","properties":{"pattern":{"type":"string"}},"required":["pattern"]}`,
		kind = .Read,
		run = tool_glob_files,
	})
	registry_register(r, Tool{
		name = "run_shell",
		description = "Run a shell command in the workspace when sandbox permits",
		schema_json = `{"type":"object","properties":{"command":{"type":"string"}},"required":["command"]}`,
		kind = .Shell,
		run = tool_run_shell,
	})
	registry_register(r, Tool{
		name = "apply_edits",
		description = "Apply multiple search-replace edits or create files atomically under the workspace",
		schema_json = `{"type":"object","properties":{"edits":{"type":"array","items":{"type":"object","properties":{"path":{"type":"string"},"old_string":{"type":"string"},"new_string":{"type":"string"},"replace_all":{"type":"string"}},"required":["path","old_string","new_string"]}},"files":{"type":"array","items":{"type":"object","properties":{"path":{"type":"string"},"content":{"type":"string"}},"required":["path","content"]}}}}`,
		kind = .Write,
		run = tool_apply_edits,
	})
	registry_register(r, Tool{
		name = "run_script",
		description = "Write and run a short script (sh/bash/python) in the workspace when sandbox permits",
		schema_json = `{"type":"object","properties":{"language":{"type":"string"},"code":{"type":"string"},"timeout_ms":{"type":"string"}},"required":["language","code"]}`,
		kind = .Shell,
		run = tool_run_script,
	})
}

registry_destroy :: proc(r: ^Registry) {
	if r == nil {
		return
	}
	delete(r.tools)
	r^ = {}
}

tools_init :: proc() {
	registry_init(&g_registry)
}

tools_destroy :: proc() {
	registry_destroy(&g_registry)
}

registry_set_external_run :: proc(r: ^Registry, p: External_Run_Proc, user: rawptr = nil) {
	if r == nil {
		return
	}
	r.external_run = p
	r.external_user = user
}

registry_register :: proc(r: ^Registry, t: Tool) {
	if r == nil {
		return
	}
	for existing, i in r.tools {
		if existing.name == t.name {
			r.tools[i] = t
			return
		}
	}
	append(&r.tools, t)
}

registry_find :: proc(r: ^Registry, name: string) -> (^Tool, bool) {
	if r == nil {
		return nil, false
	}
	for &t in r.tools {
		if t.name == name {
			return &t, true
		}
	}
	return nil, false
}

registry_list :: proc(r: ^Registry) -> []Tool {
	if r == nil {
		return {}
	}
	return r.tools[:]
}

set_external_run :: proc(p: External_Run_Proc, user: rawptr = nil) {
	registry_set_external_run(&g_registry, p, user)
}

register :: proc(t: Tool) {
	registry_register(&g_registry, t)
}

find :: proc(name: string) -> (^Tool, bool) {
	return registry_find(&g_registry, name)
}

list :: proc() -> []Tool {
	return registry_list(&g_registry)
}
