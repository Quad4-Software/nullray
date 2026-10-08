// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
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
	testing.expect(t, strings.contains(out, "url="))
	testing.expect(t, strings.contains(strings.to_lower(out, context.temp_allocator), "example"))
	testing.expect(t, !strings.contains(out, "<script"))
}

@(test)
test_html_soft_redirect_meta_and_js :: proc(t: ^testing.T) {
	meta := `<!DOCTYPE html><html><head>
<meta http-equiv="refresh" content="1; url=latest/" />
</head><body>Redirecting</body></html>`
	u, ok := html_soft_redirect_target("https://lxmfy.quad4.io/", meta)
	testing.expect(t, ok)
	testing.expect_value(t, u, "https://lxmfy.quad4.io/latest/")

	js := `<html><head><script>
window.location.replace("latest/" + window.location.search);
</script></head><body>go</body></html>`
	u2, ok2 := html_soft_redirect_target("https://lxmfy.quad4.io/", js)
	testing.expect(t, ok2)
	testing.expect_value(t, u2, "https://lxmfy.quad4.io/latest/")

	abs, aok := html_resolve_url("https://docs.example/a/b/", "/root/page")
	testing.expect(t, aok)
	testing.expect_value(t, abs, "https://docs.example/root/page")

	rel, rok := html_resolve_url("https://docs.example/a/b/page.html", "next.html")
	testing.expect(t, rok)
	testing.expect_value(t, rel, "https://docs.example/a/b/next.html")

	proto, pok := html_resolve_url("https://docs.example/x", "//cdn.example/lib.js")
	testing.expect(t, pok)
	testing.expect_value(t, proto, "https://cdn.example/lib.js")

	jsbad, jok := html_resolve_url("https://docs.example/", "javascript:alert(1)")
	testing.expect(t, !jok)
	testing.expect_value(t, jsbad, "")

	none, nok := html_soft_redirect_target("https://example.com/", "<html><body><p>Hello docs</p></body></html>")
	testing.expect(t, !nok)
	testing.expect_value(t, none, "")

	testing.expect(t, html_is_redirect_shell(meta))
	testing.expect(t, !html_is_redirect_shell("<html><body><p>docs body with enough text</p></body></html>"))
}

@(test)
test_html_soft_redirect_ssrf_target_blocks :: proc(t: ^testing.T) {
	// Soft redirect hop into loopback must be blocked by the same SSRF gate.
	body := `<!DOCTYPE html><html><head>
<meta http-equiv="refresh" content="0; url=http://127.0.0.1/secret">
</head><body>go</body></html>`
	u, ok := html_soft_redirect_target("https://evil.example/", body)
	testing.expect(t, ok)
	testing.expect_value(t, u, "http://127.0.0.1/secret")
	blocked, why := fetch_url_blocked(u)
	testing.expect(t, blocked)
	testing.expect(t, len(why) > 0)
}

@(test)
test_fetch_url_soft_redirect_live_lxmfy :: proc(t: ^testing.T) {
	// GitHub Pages versioned docs return a JS soft redirect at the apex.
	out, err := tool_fetch_url(`{"url":"https://lxmfy.quad4.io/","format":"auto","max_chars":"4000"}`, context.allocator)
	defer delete(out)
	defer delete(err)
	if err != "" {
		// Offline or blocked environments should still report cleanly.
		testing.expect(t, strings.contains(err, "fetch failed") || strings.contains(err, "blocked") || strings.contains(err, "redirect"))
		return
	}
	testing.expect(t, strings.has_prefix(out, "status=200"))
	// Soft redirect should land under /latest/ (or a version path).
	testing.expect(t, strings.contains(out, "url=https://lxmfy.quad4.io/"))
	lower := strings.to_lower(out, context.temp_allocator)
	testing.expect(t, strings.contains(lower, "lxmf") || strings.contains(lower, "reticulum") || strings.contains(lower, "quick-start"))
	testing.expect(t, !strings.contains(lower, "window.location.replace"))
}
