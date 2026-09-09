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
	gate:        int,
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
	registry_register_builtins(r)
}
registry_destroy :: proc(r: ^Registry) {
	if r == nil {
		return
	}
	snapshots_destroy()
	deferred_clear()
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
