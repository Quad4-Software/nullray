// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
#+build windows

package modules

foreign import libc "system:msvcrt"
foreign libc {
	free :: proc "c" (p: rawptr) ---
}
