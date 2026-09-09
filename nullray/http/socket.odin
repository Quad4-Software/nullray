// SPDX-License-Identifier: 0BSD
/*
TCP connection I/O with optional TLS, deadlines, and cancel polling.
*/

package http

import c "core:c"
import "core:fmt"
import "core:net"
import "core:strconv"
import "core:strings"
import "core:time"

IO_SLICE :: time.Millisecond * 500

Alpn_Proto :: enum {
	None,
	Http11,
	H2,
}

Conn :: struct {
	sock:     net.TCP_Socket,
	tls:      ^Nullray_Tls,
	use_tls:  bool,
	alpn:     Alpn_Proto,
	deadline: time.Time,
	closed:   bool,
}

Url_Parts :: struct {
	scheme:   string,
	host:     string,
	hostname: string,
	port:     int,
	path:     string,
	use_tls:  bool,
}

@(private)
parse_url :: proc(raw: string, allocator := context.temp_allocator) -> (parts: Url_Parts, err: string) {
	scheme, host, path, _, _ := net.split_url(raw, allocator)
	if scheme != "http" && scheme != "https" {
		return {}, "unsupported URL scheme"
	}
	if len(host) == 0 {
		return {}, "missing URL host"
	}
	parts.scheme = scheme
	parts.host = host
	parts.path = path
	parts.use_tls = scheme == "https"
	parts.port = parts.use_tls ? 443 : 80

	target, parse_err := net.parse_hostname_or_endpoint(host)
	if parse_err != nil {
		return {}, "invalid URL host"
	}
	switch t in target {
	case net.Endpoint:
		parts.hostname = net.address_to_string(t.address, allocator)
		if t.port != 0 {
			parts.port = t.port
		}
	case net.Host:
		parts.hostname = t.hostname
		if t.port != 0 {
			parts.port = t.port
		}
	}
	return parts, ""
}

@(private)
socket_fd :: proc(sock: net.TCP_Socket) -> c.intptr_t {
	return c.intptr_t(net.Socket(sock))
}

@(private)
net_err_string :: proc(err: net.Network_Error) -> string {
	return fmt.tprintf("%v", err)
}

@(private)
conn_set_timeouts :: proc(conn: ^Conn) {
	remain := time.diff(time.now(), conn.deadline)
	if remain <= 0 {
		remain = time.Millisecond
	}
	slice := min(remain, IO_SLICE)
	_ = net.set_option(conn.sock, .Receive_Timeout, slice)
	_ = net.set_option(conn.sock, .Send_Timeout, slice)
}

@(private)
conn_past_deadline :: proc(conn: ^Conn) -> bool {
	return time.diff(conn.deadline, time.now()) >= 0
}

conn_dial :: proc(parts: Url_Parts, timeout_sec: int) -> (conn: Conn, err: string) {
	if px := proxy_for_url(parts); px.ok {
		return conn_dial_proxy_connect(parts, px, timeout_sec)
	}
	conn.deadline = time.time_add(time.now(), time.Duration(timeout_sec) * time.Second)
	sock, dial_err := net.dial_tcp_from_hostname_with_port_override(parts.hostname, parts.port)
	if dial_err != nil {
		return {}, fmt.tprintf("connect failed: %s", net_err_string(dial_err))
	}
	conn.sock = sock
	conn.use_tls = parts.use_tls
	if !parts.use_tls {
		return conn, ""
	}
	conn.tls = nullray_tls_new()
	if conn.tls == nil {
		conn_close(&conn)
		return {}, "TLS init failed"
	}
	tls_err: [256]u8
	if nullray_tls_handshake(conn.tls, socket_fd(sock), strings.clone_to_cstring(parts.hostname, context.temp_allocator), &tls_err[0], 256) != 0 {
		msg := tls_err_buf(nil, &tls_err[0], 256)
		conn_close(&conn)
		return {}, msg
	}
	conn.alpn = .Http11
	if ap := nullray_tls_alpn(conn.tls); ap != nil {
		s := string(ap)
		if s == "h2" {
			conn.alpn = .H2
		} else if s == "http/1.1" {
			conn.alpn = .Http11
		}
	}
	return conn, ""
}

conn_close :: proc(conn: ^Conn) {
	if conn.closed {
		return
	}
	conn.closed = true
	if conn.tls != nil {
		nullray_tls_close(conn.tls)
		nullray_tls_free(conn.tls)
		conn.tls = nil
	}
	if conn.sock != 0 {
		net.close(conn.sock)
		conn.sock = 0
	}
}

conn_read :: proc(conn: ^Conn, buf: []u8) -> (n: int, err: string) {
	if len(buf) == 0 {
		return 0, ""
	}
	for {
		if cancel_requested() {
			return 0, "cancelled"
		}
		if conn_past_deadline(conn) {
			return 0, "timeout"
		}
		conn_set_timeouts(conn)
		if !conn.use_tls {
			got, recv_err := net.recv_tcp(conn.sock, buf)
			if recv_err == nil {
				return got, ""
			}
			if recv_err == .Timeout || recv_err == .Would_Block || recv_err == .Interrupted {
				continue
			}
			return got, net_err_string(recv_err)
		}
		ret := nullray_tls_read(conn.tls, raw_data(buf), c.size_t(len(buf)))
		if ret > 0 {
			return int(ret), ""
		}
		if ret == 0 {
			return 0, ""
		}
		if ret == TLS_WANT_READ || ret == TLS_WANT_WRITE {
			continue
		}
		return 0, "TLS read failed"
	}
}

conn_write :: proc(conn: ^Conn, data: []u8) -> (written: int, err: string) {
	off := 0
	for off < len(data) {
		if cancel_requested() {
			return written, "cancelled"
		}
		if conn_past_deadline(conn) {
			return written, "timeout"
		}
		conn_set_timeouts(conn)
		chunk := data[off:]
		if !conn.use_tls {
			got, send_err := net.send_tcp(conn.sock, chunk)
			written += got
			off += got
			if send_err == nil {
				if got == 0 {
					return written, "connection closed"
				}
				continue
			}
			if send_err == .Timeout || send_err == .Would_Block || send_err == .Interrupted {
				continue
			}
			return written, net_err_string(send_err)
		}
		ret := nullray_tls_write(conn.tls, raw_data(chunk), c.size_t(len(chunk)))
		if ret > 0 {
			written += int(ret)
			off += int(ret)
			continue
		}
		if ret == TLS_WANT_READ || ret == TLS_WANT_WRITE {
			continue
		}
		return written, "TLS write failed"
	}
	return written, ""
}

@(private)
read_some :: proc(c: ^Conn, buf: []u8) -> (n: int, err: string) {
	return conn_read(c, buf)
}

@(private)
read_until :: proc(c: ^Conn, acc: ^[dynamic]u8, needle: string, max: int) -> (found: bool, err: string) {
	need := len(needle)
	if need == 0 {
		return false, "invalid needle"
	}
	tmp: [4096]u8
	for len(acc^) < max {
		got, rerr := read_some(c, tmp[:])
		if rerr != "" {
			return false, rerr
		}
		if got == 0 {
			return false, "connection closed"
		}
		append(acc, ..tmp[:got])
		if len(acc^) >= need {
			data := acc^
			for i in 0 ..= len(data) - need {
				if string(data[i:i + need]) == needle {
					return true, ""
				}
			}
		}
	}
	return false, "response headers too large"
}

@(private)
parse_status_line :: proc(line: string) -> (status: int, ok: bool) {
	parts := strings.split(line, " ", context.temp_allocator)
	if len(parts) < 2 {
		return 0, false
	}
	code, parsed := strconv.parse_int(strings.trim_space(parts[1]))
	if !parsed {
		return 0, false
	}
	return code, true
}

parse_headers :: proc(header_blob: string, st: ^Header_State) {
	st.headers = make(map[string]string, context.temp_allocator)
	lines := strings.split(header_blob, "\r\n", context.temp_allocator)
	for line in lines {
		if len(line) == 0 {
			continue
		}
		key, value := header_key(line)
		if len(key) == 0 {
			continue
		}
		st.headers[key] = value
		if key == "retry-after" {
			st.retry_after = parse_retry_after(value)
		}
	}
}

@(private)
read_body :: proc(c: ^Conn, st: ^Header_State, acc: ^[dynamic]u8, max: int, prefetch: []u8 = nil) -> (err: string) {
	te, chunked := st.headers["transfer-encoding"]
	if chunked && strings.contains(strings.to_lower(te, context.temp_allocator), "chunked") {
		return read_chunked_body(c, acc, max, prefetch)
	}
	if len(prefetch) > 0 {
		if len(acc^) + len(prefetch) > max {
			return "response body too large"
		}
		append(acc, ..prefetch)
	}
	cl_str, has_len := st.headers["content-length"]
	if has_len {
		n, ok := strconv.parse_int(strings.trim_space(cl_str))
		if !ok || n < 0 {
			return "invalid Content-Length"
		}
		if n > max {
			return "response body too large"
		}
		reserve(acc, n)
		for len(acc^) < n {
			room := n - len(acc^)
			tmp: [4096]u8
			to_read := min(room, len(tmp))
			got, rerr := read_some(c, tmp[:to_read])
			if rerr != "" {
				return rerr
			}
			if got == 0 {
				return "connection closed"
			}
			append(acc, ..tmp[:got])
		}
		return ""
	}
	tmp: [4096]u8
	for {
		got, rerr := read_some(c, tmp[:])
		if rerr != "" {
			return rerr
		}
		if got == 0 {
			return ""
		}
		if len(acc^) + got > max {
			return "response body too large"
		}
		append(acc, ..tmp[:got])
	}
}

read_response :: proc(c: ^Conn, max_body: int) -> (res: Http_Result, err: string) {
	acc: [dynamic]u8
	defer delete(acc)
	st: Header_State

	found, rerr := read_until(c, &acc, "\r\n\r\n", MAX_HEADER_BYTES)
	if rerr != "" {
		return {}, rerr
	}
	if !found {
		return {}, "response headers too large"
	}

	idx := strings.index(string(acc[:]), "\r\n\r\n")
	header_blob := string(acc[:idx])
	body_start := acc[idx + 4:]

	lines := strings.split(header_blob, "\r\n", context.temp_allocator)
	if len(lines) == 0 {
		return {}, "invalid response"
	}
	status, ok := parse_status_line(lines[0])
	if !ok {
		return {}, "invalid status line"
	}
	parse_headers(strings.join(lines[1:], "\r\n", context.temp_allocator), &st)

	res.status = status
	res.retry_after = st.retry_after
	res.headers = st.headers
	res.body = make([dynamic]u8, context.temp_allocator)

	// Prefetch bytes after headers must go through chunked decoding when TE=chunked.
	// Do not append them raw onto the body.
	berr := read_body(c, &st, &res.body, max_body, body_start)
	if berr != "" {
		return {}, berr
	}
	return res, ""
}
