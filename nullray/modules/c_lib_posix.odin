// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
#+build !windows

package modules

foreign import libc "system:c"
foreign libc {
	free :: proc "c" (p: rawptr) ---
}
