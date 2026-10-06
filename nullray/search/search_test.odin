package search

import "core:encoding/json"
import "core:os"
import "core:testing"
import "core:strings"

@(test)
test_interp_url_placeholders :: proc(t: ^testing.T) {
	args := Args{query = "hello world", limit = 7, pageno = 1}
	out := interp("http://x/search?q={query}&count={limit}&p={pageno}", &args, context.temp_allocator)
	testing.expect(t, strings.contains(out, "q=hello+world") || strings.contains(out, "q=hello%20world"))
	testing.expect(t, strings.contains(out, "count=7"))
}

@(test)
test_interp_body_escapes_json :: proc(t: ^testing.T) {
	args := Args{query = `evil " quote`, limit = 3}
	out := interp_body(`{"query":"{query}"}`, &args, context.temp_allocator)
	testing.expect(t, strings.contains(out, `evil \" quote`))
}

@(test)
test_env_interp :: proc(t: ^testing.T) {
	os.set_env("NR_TEST_KEY", "sekrit")
	defer os.unset_env("NR_TEST_KEY")
	out := env_interp("Bearer ${NR_TEST_KEY} end", context.temp_allocator)
	testing.expect_value(t, out, "Bearer sekrit end")
	out2 := env_interp("x=${NR_TEST_MISSING}def", context.temp_allocator)
	testing.expect_value(t, out2, "x=def")
}

@(test)
test_json_path_nested :: proc(t: ^testing.T) {
	doc, err := json.parse_string(`{"data":{"search":[{"a":1},{"a":2}]},"hits":{"hits":[{"hit":{"repo":{"raw":"o/r"}}}]}}`, .JSON, allocator = context.temp_allocator)
	testing.expect_value(t, err, nil)
	arr := json_path(doc, "data.search")
	a, ok := arr.(json.Array)
	testing.expect(t, ok)
	testing.expect_value(t, len(a), 2)
	testing.expect_value(t, json_as_string(json_path(doc, "hits.hits.0.hit.repo.raw"), context.temp_allocator), "o/r")
	testing.expect(t, json_path(doc, "data.missing") == nil)
}

@(test)
test_map_field_dotted_and_template :: proc(t: ^testing.T) {
	doc, _ := json.parse_string(`{"hit":{"repo":{"raw":"o/r"},"path":{"raw":"src/x.go"},"ref":{"raw":"main"},"content":{"snippet":"hi"}}}`, .JSON, allocator = context.temp_allocator)
	item := json_path(doc, "hit")
	testing.expect_value(t, map_field(item, "content.snippet", context.temp_allocator), "hi")
	testing.expect_value(t,
		map_field(item, "{repo.raw} {path.raw}", context.temp_allocator), "o/r src/x.go")
	url := map_field(item, "https://github.com/{repo.raw}/blob/{ref.raw}/{path.raw}", context.temp_allocator)
	testing.expect_value(t, url, "https://github.com/o/r/blob/main/src/x.go")
	testing.expect_value(t, map_field(item, "missing.deep.path", context.temp_allocator), "")
}

@(test)
test_parse_feed_rss :: proc(t: ^testing.T) {
	body := `<?xml version="1.0"?>
<rss version="2.0"><channel>
<item><title>T1</title><link>https://a/1</link><description>D1</description><pubDate>Mon, 01 Jan 2024</pubDate></item>
<item><title>T2</title><link>https://a/2</link><description>D2</description></item>
</channel></rss>`
	res := parse_feed(body, 5, "test", context.temp_allocator)
	testing.expect_value(t, len(res), 2)
	testing.expect_value(t, res[0].title, "T1")
	testing.expect_value(t, res[0].url, "https://a/1")
	testing.expect_value(t, res[0].snippet, "D1")
	testing.expect_value(t, res[1].url, "https://a/2")
}

@(test)
test_parse_feed_atom :: proc(t: ^testing.T) {
	body := `<?xml version="1.0"?>
<feed xmlns="http://www.w3.org/2005/Atom">
<entry><title>E1</title><link href="https://b/1"/><summary>S1</summary><published>2024-01-01</published></entry>
</feed>`
	res := parse_feed(body, 5, "test", context.temp_allocator)
	testing.expect_value(t, len(res), 1)
	testing.expect_value(t, res[0].title, "E1")
	testing.expect_value(t, res[0].url, "https://b/1")
	testing.expect_value(t, res[0].date, "2024-01-01")
}

@(test)
test_opensearch_template_picks_rss :: proc(t: ^testing.T) {
	desc := `<?xml version="1.0"?>
<OpenSearchDescription xmlns="http://a9.com/-/spec/opensearch/1.1/">
<ShortName>X</ShortName><Description>d</Description>
<Url type="text/html" template="http://x/?q={searchTerms}"/>
<Url type="application/rss+xml" template="http://x/rss?q={searchTerms}&amp;c={count?}"/>
</OpenSearchDescription>`
	tpl, err := opensearch_template(desc, context.temp_allocator)
	testing.expect_value(t, err, "")
	testing.expect(t, strings.contains(tpl, "rss"))
	args := Args{query = "hi there", limit = 4}
	url := osd_substitute(tpl, &args, context.temp_allocator)
	testing.expect(t, strings.contains(url, "q=hi"))
	testing.expect(t, strings.contains(url, "c=4"))
}

@(test)
test_provider_ready_and_scope :: proc(t: ^testing.T) {
	p := Provider{kind = .Search, env_required = []string{"NR_TEST_KEY2"}}
	testing.expect(t, !provider_ready(&p))
	os.set_env("NR_TEST_KEY2", "x")
	defer os.unset_env("NR_TEST_KEY2")
	testing.expect(t, provider_ready(&p))
	p.scopes = []string{"code"}
	testing.expect(t, provider_matches_scope(&p, "code"))
	testing.expect(t, !provider_matches_scope(&p, "news"))
	testing.expect(t, provider_matches_scope(&p, ""))
}

@(test)
test_disabled_gate :: proc(t: ^testing.T) {
	testing.expect(t, enabled())
	os.set_env("NULLRAY_SEARCH", "0")
	defer os.unset_env("NULLRAY_SEARCH")
	testing.expect(t, !enabled())
}
