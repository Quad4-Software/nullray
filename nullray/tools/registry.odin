/*
Tool registry: registration, lookup, and init of built-ins.
*/

package tools

import "core:fmt"
import "core:strings"

Tool_Proc :: #type proc(args_json: string, allocator := context.allocator) -> (result: string, err: string)

External_Run_Proc :: #type proc(name: string, args_json: string, allocator := context.allocator) -> (result: string, err: string)

Tool :: struct {
	name:        string,
	description: string,
	schema_json: string,
	run:         Tool_Proc,
}

Registry :: struct {
	tools: [dynamic]Tool,
}

g_registry: Registry
g_external_run: External_Run_Proc

registry :: proc() -> ^Registry {
	return &g_registry
}

tools_init :: proc() {
	g_registry = {}
	g_registry.tools = make([dynamic]Tool)
	register(Tool{
		name = "read_file",
		description = "Read a UTF-8 text file under the workspace",
		schema_json = `{"type":"object","properties":{"path":{"type":"string"}},"required":["path"]}`,
		run = tool_read_file,
	})
	register(Tool{
		name = "write_file",
		description = "Write UTF-8 text to a file under the workspace",
		schema_json = `{"type":"object","properties":{"path":{"type":"string"},"content":{"type":"string"}},"required":["path","content"]}`,
		run = tool_write_file,
	})
	register(Tool{
		name = "list_dir",
		description = "List entries in a directory under the workspace",
		schema_json = `{"type":"object","properties":{"path":{"type":"string"}},"required":["path"]}`,
		run = tool_list_dir,
	})
	register(Tool{
		name = "edit_file",
		description = "Replace text in a UTF-8 file under the workspace",
		schema_json = `{"type":"object","properties":{"path":{"type":"string"},"old_string":{"type":"string"},"new_string":{"type":"string"},"replace_all":{"type":"string","description":"true or false"}},"required":["path","old_string","new_string"]}`,
		run = tool_edit_file,
	})
	register(Tool{
		name = "grep_files",
		description = "Search for a substring in files under the workspace",
		schema_json = `{"type":"object","properties":{"pattern":{"type":"string"},"path":{"type":"string"},"glob":{"type":"string"}},"required":["pattern"]}`,
		run = tool_grep_files,
	})
	register(Tool{
		name = "glob_files",
		description = "List files matching a glob pattern under the workspace",
		schema_json = `{"type":"object","properties":{"pattern":{"type":"string"}},"required":["pattern"]}`,
		run = tool_glob_files,
	})
	register(Tool{
		name = "run_shell",
		description = "Run a shell command in the workspace when sandbox permits",
		schema_json = `{"type":"object","properties":{"command":{"type":"string"}},"required":["command"]}`,
		run = tool_run_shell,
	})
	register(Tool{
		name = "apply_edits",
		description = "Apply multiple search-replace edits or create files atomically under the workspace",
		schema_json = `{"type":"object","properties":{"edits":{"type":"array","items":{"type":"object","properties":{"path":{"type":"string"},"old_string":{"type":"string"},"new_string":{"type":"string"},"replace_all":{"type":"string"}},"required":["path","old_string","new_string"]}},"files":{"type":"array","items":{"type":"object","properties":{"path":{"type":"string"},"content":{"type":"string"}},"required":["path","content"]}}}}`,
		run = tool_apply_edits,
	})
	register(Tool{
		name = "run_script",
		description = "Write and run a short script (sh/bash/python) in the workspace when sandbox permits",
		schema_json = `{"type":"object","properties":{"language":{"type":"string"},"code":{"type":"string"},"timeout_ms":{"type":"string"}},"required":["language","code"]}`,
		run = tool_run_script,
	})
}

tools_destroy :: proc() {
	delete(g_registry.tools)
	g_registry = {}
}

set_external_run :: proc(p: External_Run_Proc) {
	g_external_run = p
}

register :: proc(t: Tool) {
	for existing, i in g_registry.tools {
		if existing.name == t.name {
			g_registry.tools[i] = t
			return
		}
	}
	append(&g_registry.tools, t)
}

find :: proc(name: string) -> (^Tool, bool) {
	for &t in g_registry.tools {
		if t.name == name {
			return &t, true
		}
	}
	return nil, false
}

list :: proc() -> []Tool {
	return g_registry.tools[:]
}

