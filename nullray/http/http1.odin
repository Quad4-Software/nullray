// SPDX-License-Identifier: 0BSD
/*
HTTP/1.1 request encoding, redirects, and request dispatch.
*/

package http

import "core:fmt"
import "core:strconv"
import "core:strings"
import "nullray:constants"

MAX_REDIRECT_HOPS :: 5
MAX_HEADER_BYTES :: 64 * 1024

Header_State :: struct {
	retry_after: int,
	headers:     map[string]string,
}

Http_Result :: struct {
	status:      int,
	body:        [dynamic]u8,
	retry_after: int,
	headers:     map[string]string,
}

@(private)
header_key :: proc(line: string, allocator := context.temp_allocator) -> (key, value: string) {
	colon := strings.index_byte(line, ':')
	if colon < 0 {
		return "", ""
	}
	key = strings.trim_space(strings.to_lower(line[:colon], allocator))
	value = strings.trim_space(line[colon + 1:])
	return key, value
}

@(private)
parse_retry_after :: proc(value: string) -> int {
	n, ok := strconv.parse_int(strings.trim_space(value))
	if ok && n > 0 {
		return n
	}
	return 0
}

@(private)
host_header_value :: proc(parts: Url_Parts) -> string {
	// parts.host from split_url may already include :port. Always build from hostname.
	if (parts.use_tls && parts.port == 443) || (!parts.use_tls && parts.port == 80) {
		return parts.hostname
	}
	return fmt.tprintf("%s:%d", parts.hostname, parts.port)
}

build_request :: proc(
	method: string,
	parts: Url_Parts,
	headers: []string,
	body: string,
	allocator := context.temp_allocator,
) -> string {
	b := strings.builder_make(allocator)

	fmt.sbprintf(&b, "%s %s HTTP/1.1\r\n", method, parts.path)
	fmt.sbprintf(&b, "Host: %s\r\n", host_header_value(parts))
	fmt.sbprintf(&b, "User-Agent: nullray/%s\r\n", constants.VERSION)
	fmt.sbprintf(&b, "Accept: */*\r\n")
	fmt.sbprintf(&b, "Connection: close\r\n")

	has_type := false
	for h in headers {
		fmt.sbprintf(&b, "%s\r\n", h)
		lower := strings.to_lower(h, context.temp_allocator)
		if strings.has_prefix(lower, "content-type:") {
			has_type = true
		}
	}
	if len(body) > 0 && !has_type {
		fmt.sbprintf(&b, "Content-Type: application/json\r\n")
	}
	if len(body) > 0 {
		fmt.sbprintf(&b, "Content-Length: %d\r\n", len(body))
	}
	fmt.sbprintf(&b, "\r\n")
	if len(body) > 0 {
		fmt.sbprint(&b, body)
	}
	return strings.to_string(b)
}

@(private)
hex_digit :: proc(ch: rune) -> bool {
	return (ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'f') || (ch >= 'A' && ch <= 'F')
}

@(private)
parse_chunk_size :: proc(line: string) -> (size: int, ok: bool) {
	end := len(line)
	for end > 0 && (line[end - 1] == '\r' || line[end - 1] == '\n' || line[end - 1] == ' ') {
		end -= 1
	}
	s := line[:end]
	semi := strings.index_byte(s, ';')
	if semi >= 0 {
		s = s[:semi]
	}
	s = strings.trim_space(s)
	if len(s) == 0 {
		return 0, false
	}
	for ch in s {
		if !hex_digit(ch) {
			return 0, false
		}
	}
	n, parsed := strconv.parse_int(s, 16)
	if !parsed || n < 0 {
		return 0, false
	}
	return n, true
}

read_chunked_body :: proc(c: ^Conn, acc: ^[dynamic]u8, max: int, prefetch: []u8 = nil) -> (err: string) {
	line_buf: [dynamic]u8
	defer delete(line_buf)
	if len(prefetch) > 0 {
		append(&line_buf, ..prefetch)
	}
	tmp: [4096]u8

	for {
		// Ensure we have a chunk-size line
		for strings.index_byte(string(line_buf[:]), '\n') < 0 {
			got, rerr := read_some(c, tmp[:])
			if rerr != "" {
				return rerr
			}
			if got == 0 {
				return "connection closed"
			}
			append(&line_buf, ..tmp[:got])
			if len(line_buf) > 64 && strings.index_byte(string(line_buf[:]), '\n') < 0 {
				return "malformed chunk size"
			}
		}
		nl := strings.index_byte(string(line_buf[:]), '\n')
		line := string(line_buf[:nl + 1])
		size, ok := parse_chunk_size(line)
		if !ok {
			return "malformed chunk size"
		}
		rest := line_buf[nl + 1:]
		clear(&line_buf)
		append(&line_buf, ..rest)
		if size == 0 {
			return ""
		}
		if len(acc^) + size > max {
			return "response body too large"
		}
		need := size + 2
		for len(line_buf) < need {
			got, rerr := read_some(c, tmp[:])
			if rerr != "" {
				return rerr
			}
			if got == 0 {
				return "connection closed"
			}
			append(&line_buf, ..tmp[:got])
		}
		append(acc, ..line_buf[:size])
		rest = line_buf[size + 2:]
		clear(&line_buf)
		append(&line_buf, ..rest)
	}
}

@(private)
redirect_allowed :: proc(loc: string) -> bool {
	lower := strings.to_lower(loc, context.temp_allocator)
	return strings.has_prefix(lower, "http://") || strings.has_prefix(lower, "https://")
}

@(private)
resolve_redirect_url :: proc(base: Url_Parts, location: string, allocator := context.temp_allocator) -> (url: string, err: string) {
	loc := strings.trim_space(location)
	if len(loc) == 0 {
		return "", "empty redirect location"
	}
	if redirect_allowed(loc) {
		return strings.clone(loc, allocator), ""
	}
	if strings.has_prefix(loc, "/") {
		return fmt.aprintf("%s://%s%s", base.scheme, base.host, loc, allocator = allocator), ""
	}
	dir := base.path
	if i := strings.last_index_byte(dir, '/'); i >= 0 {
		dir = dir[:i + 1]
	} else {
		dir = "/"
	}
	return fmt.aprintf("%s://%s%s%s", base.scheme, base.host, dir, loc, allocator = allocator), ""
}

@(private)
should_redirect :: proc(status: int) -> bool {
	return status == 301 || status == 302 || status == 303 || status == 307 || status == 308
}

@(private)
redirect_method :: proc(method: string, status: int) -> string {
	if method == "POST" && (status == 301 || status == 302 || status == 303) {
		return "GET"
	}
	return method
}

@(private)
redirect_body :: proc(method: string, status: int, body: string) -> string {
	if method == "POST" && (status == 301 || status == 302 || status == 303) {
		return ""
	}
	return body
}

run_request :: proc(
	method: string,
	url: string,
	headers: []string,
	body: string,
	timeout_sec: int,
	max_body: int,
	allow_url: Url_Allow = nil,
) -> (status: int, resp_body: []u8, retry_after: int, err: string) {
	cur_url := strings.clone(url, context.allocator)
	defer delete(cur_url)
	cur_method := method
	cur_body := body
	hops := 0

	for {
		if allow_url != nil && !allow_url(cur_url) {
			return 0, nil, 0, "url not allowed"
		}
		parts, perr := parse_url(cur_url, context.temp_allocator)
		if perr != "" {
			return 0, nil, 0, perr
		}
		conn, derr := conn_dial(parts, timeout_sec)
		if derr != "" {
			return 0, nil, 0, derr
		}

		if conn.use_tls && conn.alpn == .H2 {
			status, body_slice, retry_after, location, herr := run_h2_request(
				&conn,
				cur_method,
				parts,
				headers,
				cur_body,
				max_body,
			)
			conn_close(&conn)
			if herr != "" {
				return 0, nil, 0, herr
			}
			if should_redirect(status) {
				if hops >= MAX_REDIRECT_HOPS {
					return 0, nil, 0, "too many redirects"
				}
				loc_trim := strings.trim_space(location)
				if len(loc_trim) == 0 {
					return status, body_slice, retry_after, ""
				}
				if strings.contains(loc_trim, "://") && !redirect_allowed(loc_trim) {
					return 0, nil, 0, "redirect to non-http URL"
				}
				next, nerr := resolve_redirect_url(parts, loc_trim, context.allocator)
				if nerr != "" {
					return 0, nil, 0, nerr
				}
				if allow_url != nil && !allow_url(next) {
					delete(next)
					return 0, nil, 0, "redirect url not allowed"
				}
				delete(cur_url)
				cur_url = next
				cur_method = redirect_method(method, status)
				cur_body = redirect_body(method, status, body)
				hops += 1
				continue
			}
			return status, body_slice, retry_after, ""
		}

		req := build_request(cur_method, parts, headers, cur_body)
		_, werr := conn_write(&conn, transmute([]u8)req)
		if werr != "" {
			conn_close(&conn)
			return 0, nil, 0, werr
		}

		res, rerr := read_response(&conn, max_body)
		conn_close(&conn)
		if rerr != "" {
			return 0, nil, 0, rerr
		}

		if should_redirect(res.status) {
			loc, has := res.headers["location"]
			if !has {
				return res.status, res.body[:], res.retry_after, ""
			}
			if hops >= MAX_REDIRECT_HOPS {
				return 0, nil, 0, "too many redirects"
			}
			loc_trim := strings.trim_space(loc)
			if strings.contains(loc_trim, "://") && !redirect_allowed(loc_trim) {
				return 0, nil, 0, "redirect to non-http URL"
			}
			next, nerr := resolve_redirect_url(parts, loc, context.allocator)
			if nerr != "" {
				return 0, nil, 0, nerr
			}
			if allow_url != nil && !allow_url(next) {
				delete(next)
				return 0, nil, 0, "redirect url not allowed"
			}
			delete(cur_url)
			cur_url = next
			cur_method = redirect_method(method, res.status)
			cur_body = redirect_body(method, res.status, body)
			hops += 1
			continue
		}
		return res.status, res.body[:], res.retry_after, ""
	}
}
