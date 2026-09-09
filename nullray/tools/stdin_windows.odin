// SPDX-License-Identifier: 0BSD
#+build windows

package tools

import win "core:sys/windows"

stdin_is_tty :: proc() -> bool {
	h := win.GetStdHandle(win.STD_INPUT_HANDLE)
	if h == win.INVALID_HANDLE_VALUE || h == nil {
		return false
	}
	mode: win.DWORD
	return bool(win.GetConsoleMode(h, &mode))
}
