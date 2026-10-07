// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Module tool registration. Reads the modules package contribution list and
appends each spec as a normal Tool, after builtins and script tools.
Module kinds map by name, so the modules package stays dependency-free.
*/

package tools

import "core:strings"
import "nullray:modules"

register_module_tools :: proc(r: ^Registry) {
	for m in modules.modules_list() {
		for spec in m.tools {
			kind: Tool_Kind
			switch spec.kind {
			case .Read:  kind = .Read
			case .Write: kind = .Write
			case .Shell: kind = .Shell
			}
			t := Tool{
				name = spec.name,
				description = spec.description,
				schema_json = spec.schema_json,
				kind = kind,
				run = spec.run,
			}
			if t.run == nil && spec.run_c != nil {
				// C modules carry a proc "c" pointer; dispatch through
				// run_named so the pointer can ride in Tool.user.
				t.run_named = module_c_trampoline
				t.user = rawptr(spec.run_c)
			}
			registry_register(r, t)
		}
	}
}

// Invokes a C module run proc. args_json is borrowed for the call; the C
// side returns a malloc'd cstring (or NULL) and may set err_out to a
// malloc'd error string. Both are copied out then freed with free().
module_c_trampoline :: proc(
	user: rawptr,
	name: string,
	args_json: string,
	allocator := context.allocator,
) -> (result: string, err: string) {
	f := transmute(modules.Run_C_Proc)user
	cargs := strings.clone_to_cstring(args_json, context.temp_allocator)
	err_out: cstring
	res := f(cargs, &err_out)
	if res != nil {
		result = strings.clone(string(res), allocator)
		modules.c_free(res)
	}
	if err_out != nil {
		err = strings.clone(string(err_out), allocator)
		modules.c_free(err_out)
	}
	return
}
