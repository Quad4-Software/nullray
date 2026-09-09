// SPDX-License-Identifier: 0BSD
/*
CSI, mouse, and UTF-8 decoding for terminal input.
*/

package ui

import "core:os"
import "core:unicode/utf8"

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
decode_utf8_lead :: proc(lead: u8) -> (ev: Event, ok: bool) {
	need := 0
	if lead & 0xe0 == 0xc0 {
		need = 2
	} else if lead & 0xf0 == 0xe0 {
		need = 3
	} else if lead & 0xf8 == 0xf0 {
		need = 4
	} else {
		return Event{kind = .Rune, ch = '\ufffd'}, true
	}
	buf: [4]u8
	buf[0] = lead
	for i in 1 ..< need {
		if !stdin_ready(8) {
			return Event{kind = .Rune, ch = '\ufffd'}, true
		}
		b, got := term_read_byte()
		if !got || (b & 0xc0) != 0x80 {
			if got {
				push_byte(b)
			}
			return Event{kind = .Rune, ch = '\ufffd'}, true
		}
		buf[i] = b
	}
	r, size := utf8.decode_rune(buf[:need])
	if size != need || r == utf8.RUNE_ERROR {
		return Event{kind = .Rune, ch = '\ufffd'}, true
	}
	return Event{kind = .Rune, ch = r}, true
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
