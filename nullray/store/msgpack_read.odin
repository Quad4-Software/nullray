// SPDX-License-Identifier: 0BSD
/*
MessagePack reader and skip helpers.
*/

package store

import "core:fmt"

Mp_Reader :: struct {
	data: []u8,
	pos:  int,
}

mp_ok :: proc(r: ^Mp_Reader) -> bool {
	return r.pos <= len(r.data)
}

mp_need :: proc(r: ^Mp_Reader, n: int) -> bool {
	return r.pos + n <= len(r.data)
}

mp_read_u8 :: proc(r: ^Mp_Reader) -> (u8, bool) {
	if !mp_need(r, 1) {
		return 0, false
	}
	v := r.data[r.pos]
	r.pos += 1
	return v, true
}

mp_read_be_u16 :: proc(r: ^Mp_Reader) -> (u16, bool) {
	if !mp_need(r, 2) {
		return 0, false
	}
	v := u16(r.data[r.pos]) << 8 | u16(r.data[r.pos + 1])
	r.pos += 2
	return v, true
}

mp_read_be_u32 :: proc(r: ^Mp_Reader) -> (u32, bool) {
	if !mp_need(r, 4) {
		return 0, false
	}
	v :=
		u32(r.data[r.pos]) << 24 |
		u32(r.data[r.pos + 1]) << 16 |
		u32(r.data[r.pos + 2]) << 8 |
		u32(r.data[r.pos + 3])
	r.pos += 4
	return v, true
}

mp_read_be_u64 :: proc(r: ^Mp_Reader) -> (u64, bool) {
	if !mp_need(r, 8) {
		return 0, false
	}
	v: u64
	for i in 0 ..< 8 {
		v = (v << 8) | u64(r.data[r.pos + i])
	}
	r.pos += 8
	return v, true
}

mp_skip_value :: proc(r: ^Mp_Reader) -> bool {
	b, ok := mp_read_u8(r)
	if !ok {
		return false
	}
	switch {
	case b <= 0x7f, b >= 0xe0 && b <= 0xff, b == 0xc0, b == 0xc2, b == 0xc3:
		return true
	case b == 0xcc:
		_, ok = mp_read_u8(r)
		return ok
	case b == 0xcd:
		_, ok = mp_read_be_u16(r)
		return ok
	case b == 0xce:
		_, ok = mp_read_be_u32(r)
		return ok
	case b == 0xcf:
		_, ok = mp_read_be_u64(r)
		return ok
	case b == 0xd0:
		_, ok = mp_read_u8(r)
		return ok
	case b == 0xd1:
		_, ok = mp_read_be_u16(r)
		return ok
	case b == 0xd2:
		_, ok = mp_read_be_u32(r)
		return ok
	case b == 0xd3:
		_, ok = mp_read_be_u64(r)
		return ok
	case b >= 0xa0 && b <= 0xbf:
		n := int(b - 0xa0)
		if !mp_need(r, n) {
			return false
		}
		r.pos += n
		return true
	case b == 0xd9:
		n8, ok2 := mp_read_u8(r)
		if !ok2 {
			return false
		}
		n := int(n8)
		if !mp_need(r, n) {
			return false
		}
		r.pos += n
		return true
	case b == 0xda:
		n16, ok2 := mp_read_be_u16(r)
		if !ok2 {
			return false
		}
		n := int(n16)
		if !mp_need(r, n) {
			return false
		}
		r.pos += n
		return true
	case b == 0xdb:
		n32, ok2 := mp_read_be_u32(r)
		if !ok2 {
			return false
		}
		n := int(n32)
		if !mp_need(r, n) {
			return false
		}
		r.pos += n
		return true
	case b >= 0x90 && b <= 0x9f:
		n := int(b - 0x90)
		for _ in 0 ..< n {
			if !mp_skip_value(r) {
				return false
			}
		}
		return true
	case b == 0xdc:
		n16, ok2 := mp_read_be_u16(r)
		if !ok2 {
			return false
		}
		for _ in 0 ..< int(n16) {
			if !mp_skip_value(r) {
				return false
			}
		}
		return true
	case b == 0xdd:
		n32, ok2 := mp_read_be_u32(r)
		if !ok2 {
			return false
		}
		for _ in 0 ..< int(n32) {
			if !mp_skip_value(r) {
				return false
			}
		}
		return true
	case b >= 0x80 && b <= 0x8f:
		n := int(b - 0x80)
		for _ in 0 ..< n {
			if !mp_skip_value(r) || !mp_skip_value(r) {
				return false
			}
		}
		return true
	case b == 0xde:
		n16, ok2 := mp_read_be_u16(r)
		if !ok2 {
			return false
		}
		for _ in 0 ..< int(n16) {
			if !mp_skip_value(r) || !mp_skip_value(r) {
				return false
			}
		}
		return true
	case b == 0xdf:
		n32, ok2 := mp_read_be_u32(r)
		if !ok2 {
			return false
		}
		for _ in 0 ..< int(n32) {
			if !mp_skip_value(r) || !mp_skip_value(r) {
				return false
			}
		}
		return true
	}
	return false
}

mp_read_str :: proc(r: ^Mp_Reader) -> (string, bool) {
	b, ok := mp_read_u8(r)
	if !ok {
		return "", false
	}
	n: int
	switch {
	case b >= 0xa0 && b <= 0xbf:
		n = int(b - 0xa0)
	case b == 0xd9:
		n8, ok2 := mp_read_u8(r)
		if !ok2 {
			return "", false
		}
		n = int(n8)
	case b == 0xda:
		n16, ok2 := mp_read_be_u16(r)
		if !ok2 {
			return "", false
		}
		n = int(n16)
	case b == 0xdb:
		n32, ok2 := mp_read_be_u32(r)
		if !ok2 {
			return "", false
		}
		n = int(n32)
	case:
		return "", false
	}
	if !mp_need(r, n) {
		return "", false
	}
	s := string(r.data[r.pos:r.pos + n])
	r.pos += n
	return s, true
}

mp_read_i64 :: proc(r: ^Mp_Reader) -> (i64, bool) {
	b, ok := mp_read_u8(r)
	if !ok {
		return 0, false
	}
	switch {
	case b <= 0x7f:
		return i64(b), true
	case b >= 0xe0:
		return i64(i8(b)), true
	case b == 0xcc:
		v, ok2 := mp_read_u8(r)
		return i64(v), ok2
	case b == 0xcd:
		v, ok2 := mp_read_be_u16(r)
		return i64(v), ok2
	case b == 0xce:
		v, ok2 := mp_read_be_u32(r)
		return i64(v), ok2
	case b == 0xcf:
		v, ok2 := mp_read_be_u64(r)
		return i64(v), ok2
	case b == 0xd0:
		v, ok2 := mp_read_u8(r)
		return i64(i8(v)), ok2
	case b == 0xd1:
		v, ok2 := mp_read_be_u16(r)
		return i64(i16(v)), ok2
	case b == 0xd2:
		v, ok2 := mp_read_be_u32(r)
		return i64(i32(v)), ok2
	case b == 0xd3:
		v, ok2 := mp_read_be_u64(r)
		return i64(v), ok2
	}
	return 0, false
}

mp_read_array_len :: proc(r: ^Mp_Reader) -> (int, bool) {
	b, ok := mp_read_u8(r)
	if !ok {
		return 0, false
	}
	switch {
	case b >= 0x90 && b <= 0x9f:
		return int(b - 0x90), true
	case b == 0xdc:
		n, ok2 := mp_read_be_u16(r)
		return int(n), ok2
	case b == 0xdd:
		n, ok2 := mp_read_be_u32(r)
		return int(n), ok2
	}
	return 0, false
}

mp_read_map_len :: proc(r: ^Mp_Reader) -> (int, bool) {
	b, ok := mp_read_u8(r)
	if !ok {
		return 0, false
	}
	switch {
	case b >= 0x80 && b <= 0x8f:
		return int(b - 0x80), true
	case b == 0xde:
		n, ok2 := mp_read_be_u16(r)
		return int(n), ok2
	case b == 0xdf:
		n, ok2 := mp_read_be_u32(r)
		return int(n), ok2
	}
	return 0, false
}
