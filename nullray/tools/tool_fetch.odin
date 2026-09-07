// SPDX-License-Identifier: 0BSD
/*
Read-only HTTP(S) fetch with SSRF basics and size caps. Not a browser.
*/

package tools

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "nullray:constants"
import nr_http "nullray:http"

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
	resp := nr_http.get(url, {}, 30, context.temp_allocator)
	if !resp.ok {
		return "", fmt.aprintf("fetch failed: %s", resp.err, allocator = allocator)
	}
	body := resp.body
	if len(body) > max_bytes {
		body = body[:max_bytes]
	}
	return fmt.aprintf("status=%d\n%s", resp.status, body, allocator = allocator), ""
}

fetch_url_blocked :: proc(url: string) -> (blocked: bool, reason: string) {
	lower := strings.to_lower(strings.trim_space(url), context.temp_allocator)
	if strings.has_prefix(lower, "file:") {
		return true, "file:// URLs are blocked"
	}
	if !(strings.has_prefix(lower, "http://") || strings.has_prefix(lower, "https://")) {
		return true, "only http(s) URLs are allowed"
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
	if colon := strings.index_byte(host, ':'); colon >= 0 {
		host = host[:colon]
	}
	host = strings.trim(host, "[]")
	if host == "localhost" || host == "metadata" || host == "metadata.google.internal" {
		return true, "link-local and metadata hosts are blocked"
	}
	if strings.has_prefix(host, "127.") || host == "0.0.0.0" {
		return true, "loopback addresses are blocked"
	}
	if strings.has_prefix(host, "169.254.") || strings.has_prefix(host, "10.") {
		return true, "private/link-local addresses are blocked"
	}
	if strings.has_prefix(host, "192.168.") || strings.has_prefix(host, "172.16.") {
		return true, "private addresses are blocked"
	}
	for i in 17 ..= 31 {
		prefix := fmt.tprintf("172.%d.", i)
		if strings.has_prefix(host, prefix) {
			return true, "private addresses are blocked"
		}
	}
	return false, ""
}
