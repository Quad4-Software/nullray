// SPDX-License-Identifier: 0BSD
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
