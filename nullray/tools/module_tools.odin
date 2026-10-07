// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Module tool registration. Reads the modules package contribution list and
appends each spec as a normal Tool, after builtins and script tools.
Module kinds map by name, so the modules package stays dependency-free.
*/

package tools

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
			registry_register(r, Tool{
				name = spec.name,
				description = spec.description,
				schema_json = spec.schema_json,
				kind = kind,
				run = spec.run,
			})
		}
	}
}
