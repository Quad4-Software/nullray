// SPDX-License-Identifier: 0BSD
package tools

import "core:strings"
import "nullray:sandbox"
import "nullray:structure"

tool_audit_structure :: proc(args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	root := workspace_root(allocator)
	defer delete(root)
	if !sandbox.path_allowed(sandbox.state(), root, false) {
		return "", strings.clone("workspace path not allowed for read", allocator)
	}
	return structure.audit(root, allocator)
}
