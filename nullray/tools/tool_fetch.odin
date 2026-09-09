// SPDX-License-Identifier: 0BSD
/*
Read-only HTTP(S) fetch with SSRF basics and size caps. Not a browser.
*/

package tools

import "core:fmt"
import "core:net"
import "core:os"
import "core:strconv"
import "core:strings"
import "nullray:constants"
import nr_http "nullray:http"
import "nullray:sandbox"

tool_fetch_url :: proc(args_json: string, allocator := context.allocator) -> (string, string) {
	url, err := json_arg_string(args_json, "url", allocator)
	if err != "" {
		return "", err
	}
	defer delete(url)
	if block, why := fetch_url_blocked(url); block {
		return "", strings.clone(why, allocator)
	}
	max_bytes := constants.DEFAULT_FETCH_MAX_BYTES
	if raw, ok := os.lookup_env(constants.ENV_FETCH_MAX_BYTES, context.temp_allocator); ok {
		if n, parsed := strconv.parse_int(strings.trim_space(raw)); parsed && n > 0 {
			max_bytes = n
		}
	}
	resp := nr_http.get_checked(url, {}, 30, fetch_url_allow_hop, context.temp_allocator)
	if !resp.ok {
		return "", fmt.aprintf("fetch failed: %s", resp.err, allocator = allocator)
	}
	body := resp.body
	if len(body) > max_bytes {
		body = body[:max_bytes]
	}
	return fmt.aprintf("status=%d\n%s", resp.status, body, allocator = allocator), ""
}

@(private)
fetch_url_allow_hop :: proc(url: string) -> bool {
	blocked, _ := fetch_url_blocked(url)
	return !blocked
}

fetch_url_blocked :: proc(url: string) -> (blocked: bool, reason: string) {
	lower := strings.to_lower(strings.trim_space(url), context.temp_allocator)
	if strings.has_prefix(lower, "file:") {
		return true, "file:// URLs are blocked"
	}
	if !(strings.has_prefix(lower, "http://") || strings.has_prefix(lower, "https://")) {
		return true, "only http(s) URLs are allowed"
	}
	if sandbox.value_looks_secret(url) {
		return true, "secret-shaped fetch URL blocked"
	}
	rest := lower
	if strings.has_prefix(rest, "https://") {
		rest = rest[8:]
	} else if strings.has_prefix(rest, "http://") {
		rest = rest[7:]
	}
	host := rest
	if slash := strings.index_byte(rest, '/'); slash >= 0 {
		host = rest[:slash]
	}
	if at := strings.index_byte(host, '@'); at >= 0 {
		host = host[at + 1:]
	}
	if colon := strings.index_byte(host, ':'); colon >= 0 && !strings.has_prefix(host, "[") {
		host = host[:colon]
	}
	host = strings.trim(host, "[]")
	if fetch_allow_blocked(host) {
		return true, "host not in NULLRAY_FETCH_ALLOW"
	}
	if host_is_blocked_literal(host) {
		return true, "link-local, loopback, and private hosts are blocked"
	}
	if host_looks_blocked_ip(host) {
		return true, "loopback and private addresses are blocked"
	}
	// Resolve and re-check so DNS rebinding / localtest.me cannot bypass.
	if resolved_host_blocked(host) {
		return true, "resolved address is loopback, link-local, or private"
	}
	return false, ""
}

@(private)
host_is_blocked_literal :: proc(host: string) -> bool {
	if host == "localhost" || host == "metadata" || host == "metadata.google.internal" {
		return true
	}
	if host == "::1" || host == "0:0:0:0:0:0:0:1" {
		return true
	}
	return false
}

@(private)
host_looks_blocked_ip :: proc(host: string) -> bool {
	if strings.has_prefix(host, "127.") || host == "0.0.0.0" {
		return true
	}
	if strings.has_prefix(host, "169.254.") || strings.has_prefix(host, "10.") {
		return true
	}
	if strings.has_prefix(host, "192.168.") || strings.has_prefix(host, "172.16.") {
		return true
	}
	for i in 17 ..= 31 {
		prefix := fmt.tprintf("172.%d.", i)
		if strings.has_prefix(host, prefix) {
			return true
		}
	}
	// CGNAT 100.64.0.0/10
	if strings.has_prefix(host, "100.") {
		parts := strings.split(host, ".", context.temp_allocator)
		if len(parts) >= 2 {
			if n, ok := strconv.parse_int(parts[1]); ok && n >= 64 && n <= 127 {
				return true
			}
		}
	}
	// Decimal / hex IPv4 forms (2130706433, 0x7f000001)
	if ip4, ok := parse_weird_ipv4(host); ok {
		return ipv4_octets_blocked(ip4[0], ip4[1], ip4[2], ip4[3])
	}
	if ip6, ok6 := net.parse_ip6_address(host); ok6 {
		return ipv6_blocked(ip6)
	}
	return false
}

@(private)
ipv6_blocked :: proc(a: net.IP6_Address) -> bool {
	// ::1 loopback
	if a == net.IP6_Loopback {
		return true
	}
	// :: (unspecified)
	if a == net.IP6_Any {
		return true
	}
	u0 := u16(a[0])
	// fc00::/7 unique local, fe80::/10 link-local, ff00::/8 multicast
	if (u0 & 0xfe00) == 0xfc00 {
		return true
	}
	if (u0 & 0xffc0) == 0xfe80 {
		return true
	}
	if (u0 & 0xff00) == 0xff00 {
		return true
	}
	// IPv4-mapped ::ffff:x.x.x.x
	if a[0] == 0 && a[1] == 0 && a[2] == 0 && a[3] == 0 && a[4] == 0 && a[5] == 0xffff {
		hi := u16(a[6])
		lo := u16(a[7])
		return ipv4_octets_blocked(u8(hi >> 8), u8(hi), u8(lo >> 8), u8(lo))
	}
	return false
}

@(private)
fetch_allow_blocked :: proc(host: string) -> bool {
	raw, ok := os.lookup_env(constants.ENV_FETCH_ALLOW, context.temp_allocator)
	if !ok || len(strings.trim_space(raw)) == 0 {
		return false
	}
	h := strings.to_lower(host, context.temp_allocator)
	copy := raw
	for part in strings.split_iterator(&copy, ",") {
		p := strings.to_lower(strings.trim_space(part), context.temp_allocator)
		if len(p) == 0 {
			continue
		}
		if h == p || strings.has_suffix(h, strings.concatenate({".", p}, context.temp_allocator)) {
			return false
		}
	}
	return true
}

@(private)
parse_weird_ipv4 :: proc(host: string) -> (octets: [4]u8, ok: bool) {
	lower := strings.to_lower(host, context.temp_allocator)
	n: u64
	parsed := false
	if strings.has_prefix(lower, "0x") {
		hex := lower[2:]
		if len(hex) == 0 || len(hex) > 8 {
			return {}, false
		}
		val: u64 = 0
		for i in 0 ..< len(hex) {
			c := hex[i]
			d: u64
			switch c {
			case '0' ..= '9':
				d = u64(c - '0')
			case 'a' ..= 'f':
				d = u64(c - 'a' + 10)
			case:
				return {}, false
			}
			val = (val << 4) | d
		}
		n = val
		parsed = true
	} else {
		all_digit := len(lower) > 0
		for i in 0 ..< len(lower) {
			if lower[i] < '0' || lower[i] > '9' {
				all_digit = false
				break
			}
		}
		if all_digit {
			if v, pok := strconv.parse_u64(lower); pok {
				n = v
				parsed = true
			}
		}
	}
	if !parsed || n > 0xffff_ffff {
		return {}, false
	}
	return [4]u8{u8(n >> 24), u8(n >> 16), u8(n >> 8), u8(n)}, true
}

@(private)
ipv4_octets_blocked :: proc(a, b, c, d: u8) -> bool {
	_ = c
	_ = d
	if a == 127 || a == 0 || a == 10 {
		return true
	}
	if a == 169 && b == 254 {
		return true
	}
	if a == 192 && b == 168 {
		return true
	}
	if a == 172 && b >= 16 && b <= 31 {
		return true
	}
	if a == 100 && b >= 64 && b <= 127 {
		return true
	}
	return false
}

@(private)
resolved_host_blocked :: proc(host: string) -> bool {
	// Skip resolve for already-numeric dotted forms handled above.
	if strings.contains(host, ".") {
		parts := strings.split(host, ".", context.temp_allocator)
		if len(parts) == 4 {
			all_num := true
			for p in parts {
				if _, ok := strconv.parse_int(p); !ok {
					all_num = false
					break
				}
			}
			if all_num {
				return false
			}
		}
	}
	if strings.contains(host, ":") {
		if ip6, ok := net.parse_ip6_address(host); ok {
			return ipv6_blocked(ip6)
		}
	}
	ep4, err4 := net.resolve_ip4(host)
	if err4 == nil {
		#partial switch a in ep4.address {
		case net.IP4_Address:
			if ipv4_octets_blocked(a[0], a[1], a[2], a[3]) {
				return true
			}
		}
	}
	ep6, err6 := net.resolve_ip6(host)
	if err6 == nil {
		#partial switch a in ep6.address {
		case net.IP6_Address:
			if ipv6_blocked(a) {
				return true
			}
		}
	}
	return false
}
