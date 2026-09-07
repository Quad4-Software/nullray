// SPDX-License-Identifier: 0BSD
/*
Key and event decoding from raw terminal input.
*/

package ui

import "core:os"

Key :: enum {
	None,
	Rune,
	Enter,
	Esc,
	Backspace,
	Tab,
	Backtab,
	Up,
	Down,
	Left,
	Right,
	Home,
	End,
	Page_Up,
	Page_Down,
	Delete,
	F1,
	F2,
	F3,
	F4,
	Ctrl_A,
	Ctrl_B,
	Ctrl_C,
	Ctrl_D,
	Ctrl_E,
	Ctrl_F,
	Ctrl_K,
	Ctrl_L,
	Ctrl_N,
	Ctrl_P,
	Ctrl_Q,
	Ctrl_R,
	Ctrl_T,
	Ctrl_U,
	Ctrl_W,
	Ctrl_Z,
	Ctrl_V,
	Ctrl_Y,
	Ctrl_J,
	Paste_Start,
	Paste_End,
	Mouse_Wheel_Up,
	Mouse_Wheel_Down,
	Mouse_Press,
	Mouse_Release,
	Mouse_Drag,
}

Event :: struct {
	kind: Key,
	ch:   rune,
	ctrl: bool,
	alt:  bool,
	mx:   int,
	my:   int,
}

poll_event :: proc(timeout_ms: int = 50) -> (ev: Event, ok: bool) {
	if _stdin_eof {
		return Event{kind = .Ctrl_C}, true
	}
	if !stdin_ready(timeout_ms) {
		return {}, false
	}
	b, got := term_read_byte()
	if !got {
		if _stdin_eof {
			return Event{kind = .Ctrl_C}, true
		}
		return {}, false
	}

	if b == 0x1b {
		if !stdin_ready(8) {
			return Event{kind = .Esc}, true
		}
		b2, got2 := term_read_byte()
		if !got2 {
			return Event{kind = .Esc}, true
		}
		if b2 == '[' {
			return decode_csi()
		}
		if b2 == 'O' {
			b3, got3 := term_read_byte()
			if got3 {
				switch b3 {
				case 'P':
					return Event{kind = .F1}, true
				case 'Q':
					return Event{kind = .F2}, true
				case 'R':
					return Event{kind = .F3}, true
				case 'S':
					return Event{kind = .F4}, true
				}
			}
		}
		return Event{kind = .Esc, alt = true, ch = rune(b2)}, true
	}

	switch b {
	case 0x01:
		return Event{kind = .Ctrl_A}, true
	case 0x02:
		return Event{kind = .Ctrl_B}, true
	case 0x03:
		return Event{kind = .Ctrl_C}, true
	case 0x04:
		return Event{kind = .Ctrl_D}, true
	case 0x05:
		return Event{kind = .Ctrl_E}, true
	case 0x06:
		return Event{kind = .Ctrl_F}, true
	case 0x0b:
		return Event{kind = .Ctrl_K}, true
	case 0x0c:
		return Event{kind = .Ctrl_L}, true
	case 0x0e:
		return Event{kind = .Ctrl_N}, true
	case 0x10:
		return Event{kind = .Ctrl_P}, true
	case 0x11:
		return Event{kind = .Ctrl_Q}, true
	case 0x12:
		return Event{kind = .Ctrl_R}, true
	case 0x14:
		return Event{kind = .Ctrl_T}, true
	case 0x15:
		return Event{kind = .Ctrl_U}, true
	case 0x17:
		return Event{kind = .Ctrl_W}, true
	case 0x1a:
		return Event{kind = .Ctrl_Z}, true
	case 0x16:
		return Event{kind = .Ctrl_V}, true
	case 0x19:
		return Event{kind = .Ctrl_Y}, true
	case 0x7f, 0x08:
		return Event{kind = .Backspace}, true
	case '\r':
		return Event{kind = .Enter}, true
	case '\n':
		return Event{kind = .Ctrl_J}, true
	case '\t':
		return Event{kind = .Tab}, true
	}

	if b >= 0x20 && b < 0x7f {
		return Event{kind = .Rune, ch = rune(b)}, true
	}
	return {}, false
}

@(private)
decode_csi :: proc() -> (ev: Event, ok: bool) {
	b3, got3 := term_read_byte()
	if !got3 {
		return Event{kind = .Esc}, true
	}

	// SGR mouse: ESC [ < btn ; col ; row M/m
	if b3 == '<' {
		btn, col, row, final, parsed := read_sgr_mouse()
		if !parsed {
			return Event{kind = .Esc}, true
		}
		mx := col - 1
		my := row - 1
		// Shift (bit 4): leave for terminal native selection when possible.
		// Still consume the event since the terminal already sent it.
		if (btn & 0x04) != 0 {
			return {}, false
		}
		wheel := btn & 0x40
		if wheel != 0 {
			if (btn & 0x01) != 0 {
				return Event{kind = .Mouse_Wheel_Down, mx = mx, my = my}, true
			}
			return Event{kind = .Mouse_Wheel_Up, mx = mx, my = my}, true
		}
		button := rune(btn & 0x03)
		if final == 'm' {
			return Event{kind = .Mouse_Release, mx = mx, my = my, ch = button}, true
		}
		if (btn & 0x20) != 0 {
			return Event{kind = .Mouse_Drag, mx = mx, my = my, ch = button}, true
		}
		return Event{kind = .Mouse_Press, mx = mx, my = my, ch = button}, true
	}

	// Legacy mouse: ESC [ M Cb Cx Cy
	if b3 == 'M' {
		cb, okb := term_read_byte()
		cx, okx := term_read_byte()
		cy, oky := term_read_byte()
		if !(okb && okx && oky) {
			return Event{kind = .Esc}, true
		}
		btn := int(cb) - 32
		mx := int(cx) - 33
		my := int(cy) - 33
		if (btn & 0x40) != 0 {
			if (btn & 0x01) != 0 {
				return Event{kind = .Mouse_Wheel_Down, mx = mx, my = my}, true
			}
			return Event{kind = .Mouse_Wheel_Up, mx = mx, my = my}, true
		}
		return Event{kind = .Mouse_Press, mx = mx, my = my, ch = rune(btn & 0x03)}, true
	}

	switch b3 {
	case 'A':
		return Event{kind = .Up}, true
	case 'B':
		return Event{kind = .Down}, true
	case 'C':
		return Event{kind = .Right}, true
	case 'D':
		return Event{kind = .Left}, true
	case 'H':
		return Event{kind = .Home}, true
	case 'F':
		return Event{kind = .End}, true
	case 'Z':
		return Event{kind = .Backtab}, true
	}

	// Parameterized CSI: ESC [ n~ or ESC [ n ; m R etc.
	if b3 >= '0' && b3 <= '9' {
		n := int(b3 - '0')
		for {
			b, got := term_read_byte()
			if !got {
				return Event{kind = .Esc}, true
			}
			if b >= '0' && b <= '9' {
				n = n * 10 + int(b - '0')
				continue
			}
			if b == ';' {
				// Skip remaining params until final byte
				for {
					b2, got2 := term_read_byte()
					if !got2 {
						return Event{kind = .Esc}, true
					}
					if b2 >= 0x40 && b2 <= 0x7e {
						break
					}
				}
				return Event{kind = .Esc}, true
			}
			if b == '~' {
				switch n {
				case 1:
					return Event{kind = .Home}, true
				case 3:
					return Event{kind = .Delete}, true
				case 4:
					return Event{kind = .End}, true
				case 5:
					return Event{kind = .Page_Up}, true
				case 6:
					return Event{kind = .Page_Down}, true
				case 200:
					return Event{kind = .Paste_Start}, true
				case 201:
					return Event{kind = .Paste_End}, true
				}
				return Event{kind = .Esc}, true
			}
			return Event{kind = .Esc}, true
		}
	}

	return Event{kind = .Esc}, true
}

@(private)
read_sgr_mouse :: proc() -> (btn, col, row: int, final: u8, ok: bool) {
	b, ok1 := read_csi_int()
	if !ok1 {
		return 0, 0, 0, 0, false
	}
	sep1, g1 := term_read_byte()
	if !g1 || sep1 != ';' {
		return 0, 0, 0, 0, false
	}
	c, ok2 := read_csi_int()
	if !ok2 {
		return 0, 0, 0, 0, false
	}
	sep2, g2 := term_read_byte()
	if !g2 || sep2 != ';' {
		return 0, 0, 0, 0, false
	}
	r, ok3 := read_csi_int()
	if !ok3 {
		return 0, 0, 0, 0, false
	}
	fin, g3 := term_read_byte()
	if !g3 || (fin != 'M' && fin != 'm') {
		return 0, 0, 0, 0, false
	}
	return b, c, r, fin, true
}

@(private)
read_csi_int :: proc() -> (n: int, ok: bool) {
	b, got := term_read_byte()
	if !got || b < '0' || b > '9' {
		return 0, false
	}
	n = int(b - '0')
	for {
		if !stdin_ready(0) {
			return n, true
		}
		b2, got2 := term_read_byte()
		if !got2 {
			return n, true
		}
		if b2 < '0' || b2 > '9' {
			// Put back by not supported. Peek was consumed.
			// Caller expects separator next. We over-read.
			// Only digits should be here, so if non-digit, treat as end and
			// we cannot unread. Use a tiny pushback.
			push_byte(b2)
			return n, true
		}
		n = n * 10 + int(b2 - '0')
	}
}

@(private)
_pushback: u8
@(private)
_has_pushback: bool
@(private)
_stdin_eof: bool

@(private)
push_byte :: proc(b: u8) {
	_pushback = b
	_has_pushback = true
}

term_read_byte :: proc() -> (b: u8, ok: bool) {
	if _has_pushback {
		_has_pushback = false
		return _pushback, true
	}
	buf: [1]u8
	n, err := os.read(os.stdin, buf[:])
	if err != nil || n <= 0 {
		_stdin_eof = true
		return 0, false
	}
	return buf[0], true
}
