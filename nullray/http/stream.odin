// SPDX-License-Identifier: 0BSD
/*
Streaming POST with SSE line delivery over HTTP/1.1.
*/

package http

import "core:fmt"
import "core:strings"
import "nullray:constants"

Stream_Chunk_Proc :: #type proc(chunk: string, user: rawptr)

MAX_STREAM_LINE_BYTES :: 256 * 1024

@(private)
flush_stream_lines :: proc(line_buf: ^[dynamic]u8, on_chunk: Stream_Chunk_Proc, user: rawptr) {
	for {
		nl := strings.index_byte(string(line_buf^[:]), '\n')
		if nl < 0 {
			break
		}
		line := string(line_buf^[:nl])
		if strings.has_suffix(line, "\r") {
			line = line[:len(line) - 1]
		}
		if on_chunk != nil {
			on_chunk(line, user)
		}
		rest := line_buf^[nl + 1:]
		clear(line_buf)
		append(line_buf, ..rest)
	}
}

run_stream_request :: proc(
	url: string,
	headers: []string,
	body: string,
	on_chunk: Stream_Chunk_Proc,
	user: rawptr,
	timeout_sec: int,
) -> (code: int, err_body: []u8, retry_after: int, err: string) {
	parts, perr := parse_url(url, context.temp_allocator)
	if perr != "" {
		return 0, nil, 0, perr
	}
	conn, derr := conn_dial(parts, timeout_sec)
	if derr != "" {
		return 0, nil, 0, derr
	}
	defer conn_close(&conn)

	if conn.use_tls && conn.alpn == .H2 {
		return run_h2_stream(&conn, parts, headers, body, on_chunk, user)
	}

	stream_headers := make([dynamic]string, context.temp_allocator)
	append(&stream_headers, ..headers)
	append(&stream_headers, "Accept: text/event-stream")

	req := build_request("POST", parts, stream_headers[:], body)
	_, werr := conn_write(&conn, transmute([]u8)req)
	if werr != "" {
		return 0, nil, 0, werr
	}

	acc: [dynamic]u8
	defer delete(acc)
	st: Header_State

	found, rerr := read_until(&conn, &acc, "\r\n\r\n", MAX_HEADER_BYTES)
	if rerr != "" {
		return 0, nil, 0, rerr
	}
	if !found {
		return 0, nil, 0, "response headers too large"
	}

	idx := strings.index(string(acc[:]), "\r\n\r\n")
	header_blob := string(acc[:idx])
	body_acc := acc[idx + 4:]

	lines := strings.split(header_blob, "\r\n", context.temp_allocator)
	if len(lines) == 0 {
		return 0, nil, 0, "invalid response"
	}
	status, ok := parse_status_line(lines[0])
	if !ok {
		return 0, nil, 0, "invalid status line"
	}
	parse_headers(strings.join(lines[1:], "\r\n", context.temp_allocator), &st)
	retry_after = st.retry_after
	code = status

	line_buf: [dynamic]u8
	defer delete(line_buf)
	append(&line_buf, ..body_acc)

	flush_stream_lines(&line_buf, on_chunk, user)

	raw: [dynamic]u8
	defer delete(raw)
	tmp: [4096]u8
	for {
		got, rd_err := read_some(&conn, tmp[:])
		if rd_err != "" {
			return code, raw[:], retry_after, rd_err
		}
		if got == 0 {
			break
		}
		if len(raw) < constants.MAX_STREAM_ERROR_BYTES {
			room := constants.MAX_STREAM_ERROR_BYTES - len(raw)
			append(&raw, ..tmp[:min(got, room)])
		}
		append(&line_buf, ..tmp[:got])
		if len(line_buf) > MAX_STREAM_LINE_BYTES {
			return code, raw[:], retry_after, "SSE line too long"
		}
		flush_stream_lines(&line_buf, on_chunk, user)
	}

	if len(line_buf) > 0 && on_chunk != nil {
		on_chunk(string(line_buf[:]), user)
	}
	return code, raw[:], retry_after, ""
}

post_json_stream :: proc(
	url: string,
	headers: []string,
	body: string,
	on_chunk: Stream_Chunk_Proc,
	user: rawptr,
	timeout_sec: int = 120,
) -> Response {
	if cancel_requested() {
		return Response{ok = false, err = "cancelled"}
	}

	status, raw, retry_after, rerr := run_stream_request(url, headers, body, on_chunk, user, timeout_sec)
	if cancel_requested() {
		return Response{ok = false, err = "cancelled"}
	}
	if rerr != "" {
		return Response{ok = false, err = strings.clone(rerr, context.allocator)}
	}
	if status >= 400 {
		err_body := strings.clone(string(raw), context.allocator)
		return Response{
			ok = false,
			status = status,
			body = err_body,
			err = fmt.tprintf("HTTP %d", status),
			retry_after = retry_after,
		}
	}
	return Response{ok = true, status = status, retry_after = retry_after}
}
