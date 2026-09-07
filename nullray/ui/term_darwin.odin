#+build darwin

/*
Darwin termios raw mode and TIOCGWINSZ via libSystem.
*/

package ui

import "core:c"
import "core:sys/posix"

Term_Plat :: struct {
	orig: posix.termios,
}

Winsize :: struct {
	ws_row:    u16,
	ws_col:    u16,
	ws_xpixel: u16,
	ws_ypixel: u16,
}

// TIOCGWINSZ on Darwin (IOC_OUT, 't', 104, sizeof(winsize)).
TIOCGWINSZ :: c.ulong(0x40087468)

foreign import libsystem "system:System"

foreign libsystem {
	ioctl :: proc(fd: c.int, request: c.ulong, #c_vararg args: ..any) -> c.int ---
}

term_plat_enter_raw :: proc(t: ^Term) -> bool {
	if posix.tcgetattr(posix.STDIN_FILENO, &t.plat.orig) != .OK {
		return false
	}
	raw := t.plat.orig
	raw.c_lflag -= {.ECHO, .ICANON, .ISIG, .IEXTEN}
	raw.c_iflag -= {.IXON, .ICRNL, .BRKINT, .INPCK, .ISTRIP}
	raw.c_oflag -= {.OPOST}
	raw.c_cc[.VMIN] = 0
	raw.c_cc[.VTIME] = 1
	if posix.tcsetattr(posix.STDIN_FILENO, .TCSANOW, &raw) != .OK {
		return false
	}
	return true
}

term_plat_leave_raw :: proc(t: ^Term) {
	_ = posix.tcsetattr(posix.STDIN_FILENO, .TCSANOW, &t.plat.orig)
}

term_plat_winsize :: proc() -> (w, h: int, ok: bool) {
	ws: Winsize
	if ioctl(c.int(posix.STDOUT_FILENO), TIOCGWINSZ, &ws) != 0 {
		return 0, 0, false
	}
	if ws.ws_col > 0 && ws.ws_row > 0 {
		return int(ws.ws_col), int(ws.ws_row), true
	}
	return 0, 0, false
}
