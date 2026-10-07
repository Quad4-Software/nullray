// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
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

// Variant that also receives the tool name and a per-tool binding (script tools).
Named_Tool_Proc :: #type proc(
	user: rawptr,
	name: string,
	args_json: string,
	allocator := context.allocator,
) -> (result: string, err: string)

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
	gate:        int,
	run:         Tool_Proc,
	run_named:   Named_Tool_Proc,
	user:        rawptr,
	from_module: bool,
}

Registry :: struct {
	tools:          [dynamic]Tool,
	external_run:   External_Run_Proc,
	external_user:  rawptr,
	// Owned Script_Tool bindings for tools registered from script dirs.
	script_tools:   [dynamic]^Script_Tool,
	// MemEx-style tool output scratchpad (stash.odin), owned per registry.
	stash:          Stash,
}

g_registry: Registry

registry :: proc() -> ^Registry {
	return &g_registry
}

registry_init :: proc(r: ^Registry) {
	r^ = {}
	r.tools = make([dynamic]Tool)
	r.script_tools = make([dynamic]^Script_Tool)
	stash_init(&r.stash)
	registry_register_builtins(r)
	register_todo_tools(r)
	register_schedule_tools(r)
	register_checkpoint_tools(r)
	// Stash readers register before script tools so a user script can
	// never shadow peek/stash_take/stash_list (see scripthooks.odin).
	register_stash_tools(r)
	// Script tools come after builtins so a same-name script can only warn,
	// never silently shadow a builtin (see scripthooks.odin).
	register_script_tools(r)
	register_module_tools(r)
}
registry_destroy :: proc(r: ^Registry) {
	if r == nil {
		return
	}
	snapshots_destroy()
	deferred_clear()
	script_tools_destroy(r)
	stash_destroy(&r.stash)
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

// Exact name match only, no alias or normalization fallback.
registry_find_exact :: proc(r: ^Registry, name: string) -> (^Tool, bool) {
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

/*
Lookup by name, falling back to the active alias table when the model was
advertised renamed tools (PA-Tool tool_names profiles). Aliases can never
shadow real names: validation keeps them disjoint from registered names and
the exact match is tried first.
*/
registry_find :: proc(r: ^Registry, name: string) -> (^Tool, bool) {
	if t, ok := registry_find_exact(r, name); ok {
		return t, true
	}
	if canonical, is_alias := tool_alias_resolve(name); is_alias && canonical != name {
		if t, ok := registry_find_exact(r, canonical); ok {
			return t, true
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
