// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package tools

import "core:fmt"
import "core:strings"
import "core:testing"

@(test)
test_rss_parse_rss2 :: proc(t: ^testing.T) {
	body := `<?xml version="1.0"?>
<rss version="2.0"><channel>
<title>Nullray News</title>
<link>https://example.com/</link>
<item>
  <title>First Post</title>
  <link>https://example.com/1</link>
  <pubDate>Mon, 01 Jan 2024 00:00:00 GMT</pubDate>
  <description>Hello &amp; welcome</description>
</item>
<item>
  <title>Second</title>
  <link>https://example.com/2</link>
  <description><![CDATA[<p>With <b>HTML</b></p>]]></description>
</item>
</channel></rss>`
	testing.expect(t, rss_looks_like(body))
	feed, ok := rss_parse(body, 10, context.allocator)
	testing.expect(t, ok)
	defer rss_destroy(&feed)
	testing.expect_value(t, feed.title, "Nullray News")
	testing.expect_value(t, len(feed.items), 2)
	testing.expect_value(t, feed.items[0].title, "First Post")
	testing.expect_value(t, feed.items[0].link, "https://example.com/1")
	testing.expect(t, strings.contains(feed.items[0].summary, "Hello & welcome"))
	testing.expect_value(t, feed.items[1].title, "Second")
	testing.expect(t, strings.contains(feed.items[1].summary, "With HTML"))

	out := rss_format(feed, "https://example.com/feed.xml", context.allocator)
	defer delete(out)
	testing.expect(t, strings.contains(out, "feed=https://example.com/feed.xml"))
	testing.expect(t, strings.contains(out, "[1] First Post"))
	testing.expect(t, strings.contains(out, "fetch_url"))
}

@(test)
test_rss_parse_atom :: proc(t: ^testing.T) {
	body := `<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Atom Feed</title>
  <link href="https://blog.example/" rel="alternate"/>
  <entry>
    <title>Hello Atom</title>
    <link href="https://blog.example/hello" rel="alternate"/>
    <updated>2024-02-01T12:00:00Z</updated>
    <summary>Atom summary text</summary>
  </entry>
</feed>`
	testing.expect(t, rss_looks_like(body))
	feed, ok := rss_parse(body, 5, context.allocator)
	testing.expect(t, ok)
	defer rss_destroy(&feed)
	testing.expect_value(t, feed.title, "Atom Feed")
	testing.expect_value(t, feed.link, "https://blog.example/")
	testing.expect_value(t, len(feed.items), 1)
	testing.expect_value(t, feed.items[0].title, "Hello Atom")
	testing.expect_value(t, feed.items[0].link, "https://blog.example/hello")
	testing.expect(t, strings.contains(feed.items[0].summary, "Atom summary"))
}

@(test)
test_rss_not_html :: proc(t: ^testing.T) {
	html := `<!DOCTYPE html><html><body><p>not a feed</p></body></html>`
	testing.expect(t, !rss_looks_like(html))
	_, ok := rss_parse(html, 5, context.allocator)
	testing.expect(t, !ok)
}

@(test)
test_rss_count_cap :: proc(t: ^testing.T) {
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	strings.write_string(&b, `<rss><channel><title>T</title>`)
	for i in 0 ..< 20 {
		strings.write_string(&b, fmt.tprintf(`<item><title>I%d</title><link>https://x/%d</link></item>`, i, i))
	}
	strings.write_string(&b, `</channel></rss>`)
	feed, ok := rss_parse(strings.to_string(b), 3, context.allocator)
	testing.expect(t, ok)
	defer rss_destroy(&feed)
	testing.expect_value(t, len(feed.items), 3)
}
