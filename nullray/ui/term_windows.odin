// SPDX-License-Identifier: 0BSD
#+build windows

/*
Windows console raw mode and screen size via Win32.
*/

package ui

import win "core:sys/windows"

Term_Plat :: struct {
	in_mode:  u32,
	out_mode: u32,
}

@(private)
g_em_active: bool
@(private)
g_em_in: u32
@(private)
g_em_out: u32

term_plat_enter_raw :: proc(t: ^Term) -> bool {
	hin := win.GetStdHandle(win.STD_INPUT_HANDLE)
	hout := win.GetStdHandle(win.STD_OUTPUT_HANDLE)
	if hin == win.INVALID_HANDLE_VALUE || hout == win.INVALID_HANDLE_VALUE {
		return false
	}
	in_mode: u32
	out_mode: u32
	if !win.GetConsoleMode(hin, &in_mode) {
		return false
	}
	if !win.GetConsoleMode(hout, &out_mode) {
		return false
	}
	t.plat.in_mode = in_mode
	t.plat.out_mode = out_mode

	new_in := in_mode
	new_in &~= win.ENABLE_ECHO_INPUT | win.ENABLE_LINE_INPUT | win.ENABLE_PROCESSED_INPUT
	new_in |= win.ENABLE_VIRTUAL_TERMINAL_INPUT | 0x0080 // ENABLE_EXTENDED_FLAGS
	new_out := out_mode | win.ENABLE_PROCESSED_OUTPUT | win.ENABLE_VIRTUAL_TERMINAL_PROCESSING
	if !win.SetConsoleMode(hin, new_in) {
		return false
	}
	if !win.SetConsoleMode(hout, new_out) {
		_ = win.SetConsoleMode(hin, t.plat.in_mode)
		return false
	}
	g_em_in = in_mode
	g_em_out = out_mode
	g_em_active = true
	return true
}

term_plat_leave_raw :: proc(t: ^Term) {
	hin := win.GetStdHandle(win.STD_INPUT_HANDLE)
	hout := win.GetStdHandle(win.STD_OUTPUT_HANDLE)
	if hin != win.INVALID_HANDLE_VALUE {
		_ = win.SetConsoleMode(hin, t.plat.in_mode)
	}
	if hout != win.INVALID_HANDLE_VALUE {
		_ = win.SetConsoleMode(hout, t.plat.out_mode)
	}
	g_em_active = false
}

term_emergency_restore :: proc "c" () {
	if !g_em_active {
		return
	}
	hin := win.GetStdHandle(win.STD_INPUT_HANDLE)
	hout := win.GetStdHandle(win.STD_OUTPUT_HANDLE)
	if hin != win.INVALID_HANDLE_VALUE {
		_ = win.SetConsoleMode(hin, g_em_in)
	}
	if hout != win.INVALID_HANDLE_VALUE {
		_ = win.SetConsoleMode(hout, g_em_out)
	}
	g_em_active = false
}

term_plat_winsize :: proc() -> (w, h: int, ok: bool) {
	hout := win.GetStdHandle(win.STD_OUTPUT_HANDLE)
	if hout == win.INVALID_HANDLE_VALUE {
		return 0, 0, false
	}
	info: win.CONSOLE_SCREEN_BUFFER_INFO
	if !win.GetConsoleScreenBufferInfo(hout, &info) {
		return 0, 0, false
	}
	cols := int(info.srWindow.Right - info.srWindow.Left + 1)
	rows := int(info.srWindow.Bottom - info.srWindow.Top + 1)
	if cols > 0 && rows > 0 {
		return cols, rows, true
	}
	return 0, 0, false
}
