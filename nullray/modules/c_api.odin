// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
C module API. A C module is a directory nullray/modules/<id>/ with a mod.c
that defines NULLRAY_MODULE_ENTRY(id) from nullray_module.h. The generated
import file foreign-imports mod.o and calls the entry from an @(init),
which calls back into these exported procs to describe itself.

Contract: run procs receive args_json as a cstring valid for the call and
return a malloc'd result string (NULL for no result), writing a malloc'd
error string through err_out when failing. Nullray frees both with free().
*/

package modules

import "base:runtime"
import "core:strings"

Run_C_Proc :: #type proc "c" (args_json: cstring, err_out: ^cstring) -> cstring

c_free :: proc "c" (p: cstring) {
	free(rawptr(p))
}

@(private)
g_pending:       Module
@(private)
g_pending_tools: [dynamic]Tool_Spec
@(private)
g_pending_cmds:  [dynamic]Command_Spec
@(private)
g_pending_open:  bool

@(private)
clone_cstr :: proc(s: cstring) -> string {
	if s == nil {
		return ""
	}
	return strings.clone(string(s))
}

@(export)
nullray_module_begin :: proc "c" (id, name, version, description: cstring) {
	context = runtime.default_context()
	g_pending_tools = make([dynamic]Tool_Spec)
	g_pending_cmds = make([dynamic]Command_Spec)
	g_pending = Module{
		id          = clone_cstr(id),
		name        = clone_cstr(name),
		version     = clone_cstr(version),
		description = clone_cstr(description),
	}
	g_pending_open = true
}

@(export)
nullray_module_add_tool :: proc "c" (
	name, description, schema_json: cstring,
	kind: int,
	run: Run_C_Proc,
) {
	context = runtime.default_context()
	if !g_pending_open {
		return
	}
	k: Kind
	switch kind {
	case 1: k = .Write
	case 2: k = .Shell
	case:   k = .Read
	}
	append(&g_pending_tools, Tool_Spec{
		name        = clone_cstr(name),
		description = clone_cstr(description),
		schema_json = clone_cstr(schema_json),
		kind        = k,
		run_c       = run,
	})
}

@(export)
nullray_module_add_command :: proc "c" (name, help, prompt: cstring) {
	context = runtime.default_context()
	if !g_pending_open {
		return
	}
	append(&g_pending_cmds, Command_Spec{
		name   = clone_cstr(name),
		help   = clone_cstr(help),
		prompt = clone_cstr(prompt),
	})
}

@(export)
nullray_module_end :: proc "c" () {
	context = runtime.default_context()
	if !g_pending_open {
		return
	}
	g_pending_open = false
	m := g_pending
	m.tools = g_pending_tools[:]
	m.commands = g_pending_cmds[:]
	modules_register(m)
}
