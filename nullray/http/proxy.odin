// SPDX-License-Identifier: 0BSD
/*
HTTP(S)_PROXY / ALL_PROXY / NO_PROXY dial support.
*/

package http

import "core:encoding/base64"
import "core:fmt"
import "core:net"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:time"

Proxy_Config :: struct {
	url:      string,
	hostname: string,
	port:     int,
	userinfo: string,
	use_tls:  bool, // unused: TLS-to-proxy not implemented
	ok:       bool,
}

proxy_enabled :: proc() -> bool {
	_, a := os.lookup_env("HTTPS_PROXY", context.temp_allocator)
	if a {
		return true
	}
	_, b := os.lookup_env("HTTP_PROXY", context.temp_allocator)
	if b {
		return true
	}
	_, c := os.lookup_env("https_proxy", context.temp_allocator)
	if c {
		return true
	}
	_, d := os.lookup_env("http_proxy", context.temp_allocator)
	if d {
		return true
	}
	_, e := os.lookup_env("ALL_PROXY", context.temp_allocator)
	if e {
		return true
	}
	_, f := os.lookup_env("all_proxy", context.temp_allocator)
	return f
}

proxy_for_url :: proc(parts: Url_Parts, allocator := context.temp_allocator) -> Proxy_Config {
	if proxy_host_excluded(parts.hostname) {
		return {}
	}
	raw := ""
	if parts.use_tls {
		if v, ok := os.lookup_env("HTTPS_PROXY", allocator); ok && len(v) > 0 {
			raw = v
		} else if v, ok := os.lookup_env("https_proxy", allocator); ok && len(v) > 0 {
			raw = v
		}
	}
	if len(raw) == 0 {
		if v, ok := os.lookup_env("HTTP_PROXY", allocator); ok && len(v) > 0 {
			raw = v
		} else if v, ok := os.lookup_env("http_proxy", allocator); ok && len(v) > 0 {
			raw = v
		}
	}
	if len(raw) == 0 {
		if v, ok := os.lookup_env("ALL_PROXY", allocator); ok && len(v) > 0 {
			raw = v
		} else if v, ok := os.lookup_env("all_proxy", allocator); ok && len(v) > 0 {
			raw = v
		}
	}
	if len(raw) == 0 {
		return {}
	}
	return parse_proxy_url(raw, allocator)
}

parse_proxy_url :: proc(raw: string, allocator := context.temp_allocator) -> Proxy_Config {
	s := strings.trim_space(raw)
	if len(s) == 0 {
		return {}
	}
	if !strings.contains(s, "://") {
		s = strings.concatenate({"http://", s}, allocator)
	}
	scheme, host, _, _, _ := net.split_url(s, allocator)
	// TLS-to-proxy is not implemented. Reject https:// so Proxy-Authorization
	// is never sent on a cleartext dial when the URL scheme claimed TLS.
	if scheme != "http" {
		return {}
	}
	if len(host) == 0 {
		return {}
	}
	out: Proxy_Config
	out.url = s
	out.use_tls = false
	out.port = 80
	userinfo := ""
	host_only := host
	if at := strings.last_index_byte(host, '@'); at >= 0 {
		userinfo = host[:at]
		host_only = host[at + 1:]
	}
	out.userinfo = userinfo
	target, err := net.parse_hostname_or_endpoint(host_only)
	if err != nil {
		return {}
	}
	switch t in target {
	case net.Endpoint:
		out.hostname = net.address_to_string(t.address, allocator)
		if t.port != 0 {
			out.port = t.port
		}
	case net.Host:
		out.hostname = t.hostname
		if t.port != 0 {
			out.port = t.port
		}
	}
	out.ok = len(out.hostname) > 0
	return out
}

proxy_host_excluded :: proc(hostname: string) -> bool {
	v, ok := os.lookup_env("NO_PROXY", context.temp_allocator)
	if !ok || len(strings.trim_space(v)) == 0 {
		v2, ok2 := os.lookup_env("no_proxy", context.temp_allocator)
		if !ok2 {
			return false
		}
		v = v2
	}
	host := strings.to_lower(hostname, context.temp_allocator)
	for part in strings.split(v, ",", context.temp_allocator) {
		p := strings.trim_space(strings.to_lower(part, context.temp_allocator))
		if len(p) == 0 {
			continue
		}
		if p == "*" {
			return true
		}
		if host == p || strings.has_suffix(host, strings.concatenate({".", p}, context.temp_allocator)) {
			return true
		}
	}
	return false
}

conn_dial_proxy_connect :: proc(parts: Url_Parts, px: Proxy_Config, timeout_sec: int) -> (conn: Conn, err: string) {
	conn.deadline = time.time_add(time.now(), time.Duration(timeout_sec) * time.Second)
	sock, dial_err := net.dial_tcp_from_hostname_with_port_override(px.hostname, px.port)
	if dial_err != nil {
		return {}, fmt.tprintf("proxy connect failed: %s", net_err_string(dial_err))
	}
	conn.sock = sock

	target := fmt.tprintf("%s:%d", parts.hostname, parts.port)
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	fmt.sbprintf(&b, "CONNECT %s HTTP/1.1\r\n", target)
	fmt.sbprintf(&b, "Host: %s\r\n", target)
	if len(px.userinfo) > 0 {
		tok, _ := base64.encode(transmute([]byte)px.userinfo, allocator = context.temp_allocator)
		fmt.sbprintf(&b, "Proxy-Authorization: Basic %s\r\n", tok)
	}
	fmt.sbprintf(&b, "Connection: keep-alive\r\n\r\n")
	req := strings.to_string(b)
	if _, werr := conn_write(&conn, transmute([]u8)req); len(werr) > 0 {
		conn_close(&conn)
		return {}, werr
	}

	buf: [1024]u8
	n, rerr := conn_read(&conn, buf[:])
	if len(rerr) > 0 {
		conn_close(&conn)
		return {}, rerr
	}
	head := string(buf[:n])
	if !strings.has_prefix(head, "HTTP/1.") {
		conn_close(&conn)
		return {}, "proxy CONNECT bad response"
	}
	sp := strings.index_byte(head, ' ')
	if sp < 0 {
		conn_close(&conn)
		return {}, "proxy CONNECT bad status"
	}
	rest := head[sp + 1:]
	code_s := rest
	if sp2 := strings.index_byte(rest, ' '); sp2 >= 0 {
		code_s = rest[:sp2]
	}
	code, _ := strconv.parse_int(code_s)
	if code != 200 {
		conn_close(&conn)
		return {}, fmt.tprintf("proxy CONNECT HTTP %d", code)
	}

	if parts.use_tls {
		conn.use_tls = true
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
			}
		}
	}
	return conn, ""
}
