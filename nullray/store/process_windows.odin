#+build windows

package store

import win "core:sys/windows"

STILL_ACTIVE :: u32(259)

@(private)
pid_alive :: proc(pid: int) -> bool {
	if pid <= 0 {
		return false
	}
	h := win.OpenProcess(win.PROCESS_QUERY_LIMITED_INFORMATION, false, u32(pid))
	if h == nil || h == win.INVALID_HANDLE_VALUE {
		return false
	}
	defer win.CloseHandle(h)
	code: u32
	if !win.GetExitCodeProcess(h, &code) {
		return false
	}
	return code == STILL_ACTIVE
}
