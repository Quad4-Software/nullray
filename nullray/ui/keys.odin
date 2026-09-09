// SPDX-License-Identifier: 0BSD
/*
Key and event decoding from raw terminal input.
*/

package ui

import "core:os"
import "core:unicode/utf8"

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
	if b >= 0x80 {
		return decode_utf8_lead(b)
	}
	return {}, false
}
