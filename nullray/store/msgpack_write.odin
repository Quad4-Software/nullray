// SPDX-License-Identifier: 0BSD
/*
MessagePack writer helpers for session transcripts.
*/

package store

mp_write_nil :: proc(b: ^[dynamic]u8) {
	append(b, 0xc0)
}

mp_write_bool :: proc(b: ^[dynamic]u8, v: bool) {
	append(b, v ? 0xc3 : 0xc2)
}

mp_write_u64 :: proc(b: ^[dynamic]u8, v: u64) {
	if v <= 0x7f {
		append(b, u8(v))
		return
	}
	if v <= 0xff {
		append(b, 0xcc, u8(v))
		return
	}
	if v <= 0xffff {
		append(b, 0xcd, u8(v >> 8), u8(v))
		return
	}
	if v <= 0xffff_ffff {
		append(b, 0xce, u8(v >> 24), u8(v >> 16), u8(v >> 8), u8(v))
		return
	}
	append(
		b,
		0xcf,
		u8(v >> 56),
		u8(v >> 48),
		u8(v >> 40),
		u8(v >> 32),
		u8(v >> 24),
		u8(v >> 16),
		u8(v >> 8),
		u8(v),
	)
}

mp_write_i64 :: proc(b: ^[dynamic]u8, v: i64) {
	if v >= 0 {
		mp_write_u64(b, u64(v))
		return
	}
	if v >= -32 {
		append(b, u8(i8(v)))
		return
	}
	if v >= -128 {
		append(b, 0xd0, u8(i8(v)))
		return
	}
	if v >= -32768 {
		u := u16(i16(v))
		append(b, 0xd1, u8(u >> 8), u8(u))
		return
	}
	if v >= -2147483648 {
		u := u32(i32(v))
		append(b, 0xd2, u8(u >> 24), u8(u >> 16), u8(u >> 8), u8(u))
		return
	}
	u := u64(v)
	append(
		b,
		0xd3,
		u8(u >> 56),
		u8(u >> 48),
		u8(u >> 40),
		u8(u >> 32),
		u8(u >> 24),
		u8(u >> 16),
		u8(u >> 8),
		u8(u),
	)
}

mp_write_str :: proc(b: ^[dynamic]u8, s: string) {
	n := len(s)
	if n <= 31 {
		append(b, u8(0xa0 + n))
	} else if n <= 0xff {
		append(b, 0xd9, u8(n))
	} else if n <= 0xffff {
		append(b, 0xda, u8(n >> 8), u8(n))
	} else {
		append(b, 0xdb, u8(n >> 24), u8(n >> 16), u8(n >> 8), u8(n))
	}
	for i in 0 ..< n {
		append(b, s[i])
	}
}

mp_write_array_hdr :: proc(b: ^[dynamic]u8, n: int) {
	if n <= 15 {
		append(b, u8(0x90 + n))
		return
	}
	if n <= 0xffff {
		append(b, 0xdc, u8(n >> 8), u8(n))
		return
	}
	append(b, 0xdd, u8(n >> 24), u8(n >> 16), u8(n >> 8), u8(n))
}

mp_write_map_hdr :: proc(b: ^[dynamic]u8, n: int) {
	if n <= 15 {
		append(b, u8(0x80 + n))
		return
	}
	if n <= 0xffff {
		append(b, 0xde, u8(n >> 8), u8(n))
		return
	}
	append(b, 0xdf, u8(n >> 24), u8(n >> 16), u8(n >> 8), u8(n))
}
