// SPDX-License-Identifier: 0BSD
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

@(private)
g_em_active: bool
@(private)
g_em_orig: posix.termios

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
	g_em_orig = t.plat.orig
	g_em_active = true
	return true
}

term_plat_leave_raw :: proc(t: ^Term) {
	_ = posix.tcsetattr(posix.STDIN_FILENO, .TCSANOW, &t.plat.orig)
	g_em_active = false
}

term_emergency_restore :: proc "c" () {
	esc := "\x1b[?2004l\x1b[?1006l\x1b[?1000l\x1b[0m\x1b[?25h\x1b[?1049l"
	_ = posix.write(posix.STDOUT_FILENO, raw_data(transmute([]u8)esc), len(esc))
	if g_em_active {
		_ = posix.tcsetattr(posix.STDIN_FILENO, .TCSANOW, &g_em_orig)
		g_em_active = false
	}
}

term_plat_winsize :: proc() -> (w, h: int, ok: bool) {
	ws: Winsize
	if ioctl(c.int(posix.STDOUT_FILENO), TIOCGWINSZ, &ws) == 0 && ws.ws_col > 0 && ws.ws_row > 0 {
		return int(ws.ws_col), int(ws.ws_row), true
	}
	if ioctl(c.int(posix.STDIN_FILENO), TIOCGWINSZ, &ws) == 0 && ws.ws_col > 0 && ws.ws_row > 0 {
		return int(ws.ws_col), int(ws.ws_row), true
	}
	return 0, 0, false
}
