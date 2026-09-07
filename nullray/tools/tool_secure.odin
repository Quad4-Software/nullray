// SPDX-License-Identifier: 0BSD
package tools

import "core:strings"
import "nullray:sandbox"
import "nullray:secure"

tool_audit_actions :: proc(args_json: string, allocator := context.allocator) -> (string, string) {
	return run_secure_audit(secure.audit_actions, allocator)
}

tool_audit_dockerfile :: proc(args_json: string, allocator := context.allocator) -> (string, string) {
	return run_secure_audit(secure.audit_dockerfile, allocator)
}

tool_audit_compose :: proc(args_json: string, allocator := context.allocator) -> (string, string) {
	return run_secure_audit(secure.audit_compose, allocator)
}

tool_audit_owasp :: proc(args_json: string, allocator := context.allocator) -> (string, string) {
	return run_secure_audit(secure.audit_owasp, allocator)
}

tool_audit_deps :: proc(args_json: string, allocator := context.allocator) -> (string, string) {
	return run_secure_audit(secure.audit_deps, allocator)
}

run_secure_audit :: proc(scanner: secure.Scanner_Proc, allocator := context.allocator) -> (string, string) {
	root := workspace_root(allocator)
	defer delete(root)
	if !sandbox.path_allowed(sandbox.state(), root, false) {
		return "", strings.clone("workspace path not allowed for read", allocator)
	}
	return scanner(root, allocator), ""
}
