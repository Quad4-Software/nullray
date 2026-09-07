// SPDX-License-Identifier: 0BSD
package tools

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
	}
	for c in cases {
		blocked, _ := fetch_url_blocked(c)
		testing.expectf(t, blocked, "expected block %s", c)
	}
	ok_blocked, _ := fetch_url_blocked("https://example.com/docs")
	testing.expect(t, !ok_blocked)
}
