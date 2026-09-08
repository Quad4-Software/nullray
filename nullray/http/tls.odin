// SPDX-License-Identifier: 0BSD
/*
Thin Odin bindings for the nullray Mbed TLS C shim.
*/

package http

import "core:c"

foreign import nullray_tls {
	"../../lib/libnullray_tls.a",
}

Nullray_Tls :: struct {}

TLS_WANT_READ  :: -2
TLS_WANT_WRITE :: -3

@(default_calling_convention = "c")
foreign nullray_tls {
	nullray_tls_global_init    :: proc() -> c.int ---
	nullray_tls_global_cleanup :: proc() ---

	nullray_tls_new   :: proc() -> ^Nullray_Tls ---
	nullray_tls_free  :: proc(t: ^Nullray_Tls) ---

	nullray_tls_load_cas     :: proc(t: ^Nullray_Tls, err: [^]u8, err_len: c.size_t) -> c.int ---
	nullray_tls_handshake    :: proc(t: ^Nullray_Tls, fd: c.intptr_t, hostname: cstring, err: [^]u8, err_len: c.size_t) -> c.int ---
	nullray_tls_alpn         :: proc(t: ^Nullray_Tls) -> cstring ---
	nullray_tls_read         :: proc(t: ^Nullray_Tls, buf: [^]u8, len: c.size_t) -> c.int ---
	nullray_tls_write        :: proc(t: ^Nullray_Tls, buf: [^]u8, len: c.size_t) -> c.int ---
	nullray_tls_close        :: proc(t: ^Nullray_Tls) ---

	nullray_h2_request :: proc(
		read_fn: rawptr,
		write_fn: rawptr,
		stop_fn: rawptr,
		io_ctx: rawptr,
		method: cstring,
		path: cstring,
		authority: cstring,
		scheme: cstring,
		headers: [^]Nullray_H2_Header,
		nheaders: c.size_t,
		body: [^]u8,
		body_len: c.size_t,
		status_out: ^c.int,
		body_out: [^]u8,
		body_cap: c.size_t,
		body_len_out: ^c.size_t,
		retry_after_out: ^c.int,
		location_out: [^]u8,
		location_len: c.size_t,
		err: [^]u8,
		err_len: c.size_t,
	) -> c.int ---

	nullray_h2_request_stream :: proc(
		read_fn: rawptr,
		write_fn: rawptr,
		stop_fn: rawptr,
		io_ctx: rawptr,
		method: cstring,
		path: cstring,
		authority: cstring,
		scheme: cstring,
		headers: [^]Nullray_H2_Header,
		nheaders: c.size_t,
		body: [^]u8,
		body_len: c.size_t,
		on_data: rawptr,
		on_data_user: rawptr,
		status_out: ^c.int,
		err_body: [^]u8,
		err_cap: c.size_t,
		err_len_out: ^c.size_t,
		retry_after_out: ^c.int,
		err: [^]u8,
		err_len: c.size_t,
	) -> c.int ---
}

@(private)
tls_err_buf :: proc(err: cstring, buf: [^]u8, n: int) -> string {
	if err != nil {
		return string(err)
	}
	end := 0
	for end < n && buf[end] != 0 {
		end += 1
	}
	if end > 0 {
		return string(buf[:end])
	}
	return "TLS error"
}
