// SPDX-License-Identifier: 0BSD
package tools

import "core:strings"
import "core:testing"

@(test)
test_fetch_url_blocks_ssrf :: proc(t: ^testing.T) {
	cases := []string{
		"file:///etc/passwd",
		"http://127.0.0.1/x",
		"https://localhost/x",
		"http://169.254.169.254/latest",
		"http://10.0.0.1/",
		"http://192.168.1.1/",
		"ftp://example.com/",
		"http://2130706433/",
		"http://0x7f000001/",
		"http://100.64.0.1/",
		"http://[::1]/",
	}
	for c in cases {
		blocked, _ := fetch_url_blocked(c)
		testing.expectf(t, blocked, "expected block %s", c)
	}
	ok_blocked, _ := fetch_url_blocked("https://example.com/docs")
	testing.expect(t, !ok_blocked)
}

@(test)
test_fetch_url_kind_is_read :: proc(t: ^testing.T) {
	reg: Registry
	registry_init(&reg)
	defer registry_destroy(&reg)
	ok, reason := tool_kind_allowed(&reg, "fetch_url", "ask")
	testing.expect(t, ok)
	testing.expect(t, reason == "")
	ok2, _ := tool_kind_allowed(&reg, "fetch_url", "plan")
	testing.expect(t, ok2)
}

@(test)
test_fetch_url_live_example :: proc(t: ^testing.T) {
	out, err := tool_fetch_url(`{"url":"https://example.com/","format":"auto","max_chars":"8000"}`, context.allocator)
	defer delete(out)
	if err != "" {
		testing.expect(t, strings.contains(err, "fetch failed") || strings.contains(err, "blocked"))
		return
	}
	testing.expect(t, strings.has_prefix(out, "status=200"))
	testing.expect(t, strings.contains(out, "format="))
	testing.expect(t, strings.contains(strings.to_lower(out, context.temp_allocator), "example"))
	testing.expect(t, !strings.contains(out, "<script"))
}
