// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Module registry. A module is a directory under nullray/modules/<id>/ whose
mod.odin calls modules_register from an @(init) proc. The build regenerates
cmd/nullray/modules_gen.odin (scripts/gen_modules.odin) with a side-effect
import per directory, so adding or removing a module is just a folder plus
make, with no core file edits.

This package must stay a leaf: it imports nothing from the repo so any
other package can read the contribution list without import cycles.
*/

package modules

import "base:runtime"
import "core:os"
import "core:strings"

Kind :: enum {
	Read,
	Write,
	Shell,
}

Run_Proc :: #type proc(args_json: string, allocator := context.allocator) -> (result: string, err: string)

Tool_Spec :: struct {
	name:        string,
	description: string,
	schema_json: string,
	kind:        Kind,
	run:         Run_Proc,
	run_c:       Run_C_Proc, // C module entry point, see c_api.odin
}

Command_Spec :: struct {
	name:   string,
	help:   string,
	prompt: string, // template, $ARGUMENTS and $1..$9 expand like custom commands
}

Module :: struct {
	id:          string,
	name:        string,
	version:     string,
	description: string,
	tools:       []Tool_Spec,
	commands:    []Command_Spec,
}

@(private)
g_modules: [dynamic]Module

// Called from @(init) procs, which run contextless. The module literal is
// evaluated in the caller's context, so the caller installs a context
// first, this proc assumes nothing about context.
modules_register :: proc(m: Module) {
	if !module_enabled(m.id) {
		return
	}
	append(&g_modules, m)
}

modules_list :: proc() -> []Module {
	return g_modules[:]
}

// Test support: clears all registered modules.
modules_reset :: proc() {
	clear(&g_modules)
}

// NULLRAY_MODULES: unset or "all" loads every module, "off"/"none" loads
// none, a CSV allowlist loads just those ids.
module_enabled :: proc(id: string) -> bool {
	v, ok := os.lookup_env("NULLRAY_MODULES", context.temp_allocator)
	if !ok {
		return true
	}
	l := strings.to_lower(strings.trim_space(v), context.temp_allocator)
	switch l {
	case "off", "none", "0", "false":
		return false
	case "", "all", "*":
		return true
	}
	for tok in strings.split(l, ",", context.temp_allocator) {
		if strings.trim_space(tok) == id {
			return true
		}
	}
	return false
}
