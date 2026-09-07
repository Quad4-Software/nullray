#+build windows

/*
stdin_ready via WaitForSingleObject on the console input handle.
*/

package ui

import win "core:sys/windows"

@(private)
stdin_ready :: proc(timeout_ms: int) -> bool {
	if _has_pushback {
		return true
	}
	hin := win.GetStdHandle(win.STD_INPUT_HANDLE)
	if hin == win.INVALID_HANDLE_VALUE {
		return false
	}
	wait := u32(timeout_ms)
	if timeout_ms < 0 {
		wait = win.INFINITE
	}
	r := win.WaitForSingleObject(hin, wait)
	return r == win.WAIT_OBJECT_0
}
