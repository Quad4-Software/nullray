// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
#+build windows
package elevate

ensure_askpass_helper :: proc(allocator := context.allocator) -> string {
	_ = allocator
	return ""
}
