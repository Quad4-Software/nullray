// SPDX-License-Identifier: 0BSD
#+build windows
package elevate

ensure_askpass_helper :: proc(allocator := context.allocator) -> string {
	_ = allocator
	return ""
}
