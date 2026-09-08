// SPDX-License-Identifier: 0BSD
/*
HTTP/2 request path via vendored nghttp2 (ALPN h2).
*/

package http

import "base:runtime"
import "core:c"
	import "core:fmt"
import "core:strings"
import "nullray:constants"

Nullray_H2_Header :: struct {
	name:  cstring,
	value: cstring,
}

H2_Io :: struct {
	conn: ^Conn,
}

H2_Stream_State :: struct {
	line_buf: [dynamic]u8,
	on_chunk: Stream_Chunk_Proc,
	user:     rawptr,
	err:      string,
}

@(private)
h2_read_cb :: proc "c" (ctx: rawptr, buf: [^]u8, length: c.size_t) -> c.int {
	context = runtime.default_context()
	io := cast(^H2_Io)ctx
	if io == nil || io.conn == nil || buf == nil || length == 0 {
		return -1
	}
	n, err := conn_read(io.conn, buf[:int(length)])
	if err == "cancelled" || err == "timeout" {
		return -1
	}
	if err != "" {
		return -1
	}
	return c.int(n)
}

@(private)
h2_write_cb :: proc "c" (ctx: rawptr, buf: [^]u8, length: c.size_t) -> c.int {
	context = runtime.default_context()
	io := cast(^H2_Io)ctx
	if io == nil || io.conn == nil || buf == nil || length == 0 {
		return -1
	}
	n, err := conn_write(io.conn, buf[:int(length)])
	if err != "" {
		return -1
	}
	return c.int(n)
}

@(private)
h2_stop_cb :: proc "c" (ctx: rawptr) -> c.int {
	context = runtime.default_context()
	io := cast(^H2_Io)ctx
	if io == nil || io.conn == nil {
		return 1
	}
	if cancel_requested() {
		return 1
	}
	if conn_past_deadline(io.conn) {
		return 1
	}
	return 0
}

@(private)
h2_stream_data_cb :: proc "c" (data: [^]u8, length: c.size_t, user: rawptr) {
	context = runtime.default_context()
	st := cast(^H2_Stream_State)user
	if st == nil || data == nil || length == 0 {
		return
	}
	append(&st.line_buf, ..data[:int(length)])
	if len(st.line_buf) > MAX_STREAM_LINE_BYTES {
		st.err = "SSE line too long"
		return
	}
	flush_stream_lines(&st.line_buf, st.on_chunk, st.user)
}

@(private)
h2_skip_header :: proc(name: string) -> bool {
	lower := strings.to_lower(name, context.temp_allocator)
	switch lower {
	case "host", "connection", "keep-alive", "proxy-connection", "transfer-encoding", "upgrade", "te":
		return true
	}
	return false
}

@(private)
h2_append_header_line :: proc(dst: ^[dynamic]Nullray_H2_Header, line: string) {
	colon := strings.index_byte(line, ':')
	if colon <= 0 {
		return
	}
	name := strings.trim_space(line[:colon])
	value := strings.trim_space(line[colon + 1:])
	if h2_skip_header(name) {
		return
	}
	append(dst, Nullray_H2_Header{
		name = strings.clone_to_cstring(strings.to_lower(name, context.temp_allocator), context.temp_allocator),
		value = strings.clone_to_cstring(value, context.temp_allocator),
	})
}

@(private)
h2_build_headers :: proc(
	headers: []string,
	extra: []string = {},
	allocator := context.temp_allocator,
) -> [dynamic]Nullray_H2_Header {
	out := make([dynamic]Nullray_H2_Header, allocator)
	for h in headers {
		h2_append_header_line(&out, h)
	}
	for h in extra {
		h2_append_header_line(&out, h)
	}
	return out
}

@(private)
h2_authority :: proc(parts: Url_Parts) -> string {
	return host_header_value(parts)
}

run_h2_request :: proc(
	conn: ^Conn,
	method: string,
	parts: Url_Parts,
	headers: []string,
	body: string,
	max_body: int,
) -> (status: int, resp_body: []u8, retry_after: int, location: string, err: string) {
	io := H2_Io{conn = conn}
	hdrs := h2_build_headers(headers)
	if len(body) > 0 {
		has_type := false
		for h in headers {
			if strings.has_prefix(strings.to_lower(h, context.temp_allocator), "content-type:") {
				has_type = true
				break
			}
		}
		if !has_type {
			append(&hdrs, Nullray_H2_Header{
				name = "content-type",
				value = "application/json",
			})
		}
	}
	append(&hdrs, Nullray_H2_Header{
		name = "user-agent",
		value = strings.clone_to_cstring(fmt.tprintf("nullray/%s", constants.VERSION), context.temp_allocator),
	})
	append(&hdrs, Nullray_H2_Header{name = "accept", value = "*/*"})

	body_buf := make([]u8, max_body, context.temp_allocator)
	status_c: c.int
	body_len: c.size_t
	retry_c: c.int
	err_buf: [256]u8
	loc_buf: [1024]u8

	body_ptr: [^]u8 = nil
	body_n: c.size_t = 0
	if len(body) > 0 {
		body_ptr = raw_data(transmute([]u8)body)
		body_n = c.size_t(len(body))
	}

	rc := nullray_h2_request(
		rawptr(h2_read_cb),
		rawptr(h2_write_cb),
		rawptr(h2_stop_cb),
		&io,
		strings.clone_to_cstring(method, context.temp_allocator),
		strings.clone_to_cstring(parts.path, context.temp_allocator),
		strings.clone_to_cstring(h2_authority(parts), context.temp_allocator),
		strings.clone_to_cstring(parts.scheme, context.temp_allocator),
		raw_data(hdrs[:]),
		c.size_t(len(hdrs)),
		body_ptr,
		body_n,
		&status_c,
		raw_data(body_buf),
		c.size_t(len(body_buf)),
		&body_len,
		&retry_c,
		&loc_buf[0],
		1024,
		&err_buf[0],
		256,
	)
	if rc != 0 {
		if cancel_requested() {
			return 0, nil, 0, "", "cancelled"
		}
		if conn_past_deadline(conn) {
			return 0, nil, 0, "", "timeout"
		}
		return 0, nil, 0, "", tls_err_buf(nil, &err_buf[0], 256)
	}
	loc_end := 0
	for loc_end < len(loc_buf) && loc_buf[loc_end] != 0 {
		loc_end += 1
	}
	return int(status_c), body_buf[:int(body_len)], int(retry_c), string(loc_buf[:loc_end]), ""
}

run_h2_stream :: proc(
	conn: ^Conn,
	parts: Url_Parts,
	headers: []string,
	body: string,
	on_chunk: Stream_Chunk_Proc,
	user: rawptr,
) -> (status: int, err_body: []u8, retry_after: int, err: string) {
	io := H2_Io{conn = conn}
	st: H2_Stream_State
	st.line_buf = make([dynamic]u8, context.allocator)
	defer delete(st.line_buf)
	st.on_chunk = on_chunk
	st.user = user

	hdrs := h2_build_headers(headers, {"Accept: text/event-stream"})
	has_type := false
	for h in headers {
		if strings.has_prefix(strings.to_lower(h, context.temp_allocator), "content-type:") {
			has_type = true
			break
		}
	}
	if len(body) > 0 && !has_type {
		append(&hdrs, Nullray_H2_Header{name = "content-type", value = "application/json"})
	}
	append(&hdrs, Nullray_H2_Header{
		name = "user-agent",
		value = strings.clone_to_cstring(fmt.tprintf("nullray/%s", constants.VERSION), context.temp_allocator),
	})

	raw := make([]u8, constants.MAX_STREAM_ERROR_BYTES, context.temp_allocator)
	status_c: c.int
	err_len: c.size_t
	retry_c: c.int
	err_buf: [256]u8

	body_ptr: [^]u8 = nil
	body_n: c.size_t = 0
	if len(body) > 0 {
		body_ptr = raw_data(transmute([]u8)body)
		body_n = c.size_t(len(body))
	}

	rc := nullray_h2_request_stream(
		rawptr(h2_read_cb),
		rawptr(h2_write_cb),
		rawptr(h2_stop_cb),
		&io,
		cstring("POST"),
		strings.clone_to_cstring(parts.path, context.temp_allocator),
		strings.clone_to_cstring(h2_authority(parts), context.temp_allocator),
		strings.clone_to_cstring(parts.scheme, context.temp_allocator),
		raw_data(hdrs[:]),
		c.size_t(len(hdrs)),
		body_ptr,
		body_n,
		rawptr(h2_stream_data_cb),
		&st,
		&status_c,
		raw_data(raw),
		c.size_t(len(raw)),
		&err_len,
		&retry_c,
		&err_buf[0],
		256,
	)
	if st.err != "" {
		return int(status_c), raw[:int(err_len)], int(retry_c), st.err
	}
	if len(st.line_buf) > 0 && on_chunk != nil {
		on_chunk(string(st.line_buf[:]), user)
	}
	if rc != 0 {
		if cancel_requested() {
			return 0, nil, 0, "cancelled"
		}
		if conn_past_deadline(conn) {
			return 0, nil, 0, "timeout"
		}
		return 0, nil, 0, tls_err_buf(nil, &err_buf[0], 256)
	}
	return int(status_c), raw[:int(err_len)], int(retry_c), ""
}
