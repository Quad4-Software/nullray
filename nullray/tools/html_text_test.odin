// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package tools

import "core:strings"
import "core:testing"

@(test)
test_html_to_readable_text :: proc(t: ^testing.T) {
	html := `<!doctype html><html><head><style>body{}</style><script>evil()</script></head>` +
		`<body><h1>Title&amp;More</h1><p>Hello&nbsp;world</p><br/><div>Line two</div></body></html>`
	testing.expect(t, html_looks_like(html))
	out := html_to_readable_text(html, context.allocator)
	defer delete(out)
	testing.expect(t, !strings.contains(out, "evil"))
	testing.expect(t, !strings.contains(out, "body{}"))
	testing.expect(t, strings.contains(out, "Title&More"))
	testing.expect(t, strings.contains(out, "Hello world"))
	testing.expect(t, strings.contains(out, "Line two"))
}

@(test)
test_html_entity_and_script_strip :: proc(t: ^testing.T) {
	html := "<html><script>alert(1)</script><p>A&amp;B</p><p>C&#39;D</p></html>"
	out := html_to_readable_text(html, context.allocator)
	defer delete(out)
	testing.expect(t, !strings.contains(out, "alert"))
	testing.expect(t, strings.contains(out, "A&B"))
	testing.expect(t, strings.contains(out, "C'D"))
}

@(test)
test_html_looks_like_plain :: proc(t: ^testing.T) {
	testing.expect(t, !html_looks_like("just plain text about numbers 123"))
	testing.expect(t, html_looks_like("<!DOCTYPE HTML><html><body>x</body></html>"))
}

@(test)
test_html_title_and_links :: proc(t: ^testing.T) {
	html := `<!doctype html><html><head><title>LXMFy &amp; Docs</title></head>` +
		`<body><h1>Guide</h1><p>See <a href="./quick-start/">Quick Start</a> and ` +
		`<a href="https://example.com/api">API</a>.</p></body></html>`
	title := html_document_title(html)
	testing.expect_value(t, title, "LXMFy & Docs")
	out := html_to_readable_text(html, context.allocator)
	defer delete(out)
	testing.expect(t, strings.contains(out, "Guide"))
	testing.expect(t, strings.contains(out, "Quick Start (./quick-start/)"))
	testing.expect(t, strings.contains(out, "API (https://example.com/api)"))
	testing.expect(t, !strings.contains(out, "<a "))
}

@(test)
test_fetch_url_returns_title_and_links :: proc(t: ^testing.T) {
	out, err := tool_fetch_url(`{"url":"https://example.com/","format":"auto","max_chars":"4000"}`, context.allocator)
	defer delete(out)
	defer delete(err)
	if err != "" {
		testing.expect(t, strings.contains(err, "fetch failed") || strings.contains(err, "blocked"))
		return
	}
	testing.expect(t, strings.has_prefix(out, "status=200"))
	testing.expect(t, strings.contains(out, "url="))
	// example.com usually has a title; tolerate offline variation.
	lower := strings.to_lower(out, context.temp_allocator)
	testing.expect(t, strings.contains(lower, "example") || strings.contains(out, "title="))
}
