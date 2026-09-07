// SPDX-License-Identifier: 0BSD
#+build windows

package run

import "core:os"
import win "core:sys/windows"

stdin_is_tty :: proc() -> bool {
	h := win.GetStdHandle(win.STD_INPUT_HANDLE)
	if h == win.INVALID_HANDLE_VALUE || h == nil {
		return false
	}
	mode: win.DWORD
	return bool(win.GetConsoleMode(h, &mode))
}

read_all_stdin :: proc(allocator := context.allocator) -> (string, bool) {
	if stdin_is_tty() {
		return "", false
	}
	data, err := os.read_entire_file(os.stdin, allocator)
	if err != nil {
		return "", false
	}
	return string(data), true
}
