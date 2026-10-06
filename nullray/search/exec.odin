// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Request execution and result parsing. Placeholders {query} {limit}
{pageno} {lang} {url} {extra} substitute into url/body/headers; ${ENV}
reads a secret from the environment (empty when unset, so a missing
${FIRECRAWL_API_URL} collapses to the hosted URL). Results normalize to
title/url/snippet triples either through a dotted results_path map or by
parsing RSS/Atom bodies directly (OpenSearch path).
*/

package search

import "core:encoding/json"
import "core:fmt"
import "core:net"
import "core:os"
import "core:strconv"
import "core:strings"
import nr_http "nullray:http"

Args :: struct {
	query:      string,
	url:        string, // fetch-kind providers
	limit:      int,
	pageno:     int,
	lang:       string,
	extra:      string, // pre-built "&engines=a,b&categories=x" passthrough
	max_body:   int,
}

@(private)
interp :: proc(tpl: string, args: ^Args, allocator := context.allocator) -> string {
	// ${ENV} first so env values can also carry placeholders.
	out := env_interp(tpl, context.temp_allocator)
	if args == nil {
		return strings.clone(out, allocator)
	}
	q := net.percent_encode(args.query, context.temp_allocator)
	u := net.percent_encode(args.url, context.temp_allocator)
	// raw JSON-escaped forms for bodies: {query} inside a quoted JSON string
	// must escape quotes; providers put {query} inside quotes, so substitute
	// the escaped text in body and the percent form in url.
	b := strings.builder_make(context.temp_allocator)
	i := 0
	for i < len(out) {
		c := out[i]
		if c == '{' {
			end := strings.index_byte(out[i:], '}')
			if end > 0 {
				key := out[i + 1 : i + end]
				if !valid_placeholder(key) {
					strings.write_byte(&b, c)
					i += 1
					continue
				}
				i += end + 1
				switch key {
				case "query":  strings.write_string(&b, q)
				case "url":    strings.write_string(&b, u)
				case "limit":  strings.write_int(&b, args.limit)
				case "pageno": strings.write_int(&b, args.pageno)
				case "lang":   strings.write_string(&b, args.lang)
				case "extra":  strings.write_string(&b, args.extra)
				case:
					strings.write_byte(&b, '{')
					strings.write_string(&b, key)
					strings.write_byte(&b, '}')
				}
				continue
			}
		}
		strings.write_byte(&b, c)
		i += 1
	}
	return strings.clone(strings.to_string(b), allocator)
}

// Same substitution for JSON bodies, but {query}/{url} land inside quoted
// strings so they need JSON escaping, not percent encoding.
@(private)
interp_body :: proc(tpl: string, args: ^Args, allocator := context.allocator) -> string {
	out := env_interp(tpl, context.temp_allocator)
	if args == nil {
		return strings.clone(out, allocator)
	}
	q := json_str_escape(args.query, context.temp_allocator)
	u := json_str_escape(args.url, context.temp_allocator)
	b := strings.builder_make(context.temp_allocator)
	i := 0
	for i < len(out) {
		c := out[i]
		if c == '{' {
			end := strings.index_byte(out[i:], '}')
			if end > 0 {
				key := out[i + 1 : i + end]
				if !valid_placeholder(key) {
					strings.write_byte(&b, c)
					i += 1
					continue
				}
				i += end + 1
				switch key {
				case "query":  strings.write_string(&b, q)
				case "url":    strings.write_string(&b, u)
				case "limit":  strings.write_int(&b, args.limit)
				case "pageno": strings.write_int(&b, args.pageno)
				case "lang":   strings.write_string(&b, args.lang)
				case "extra":  strings.write_string(&b, args.extra)
				case:
					strings.write_byte(&b, '{')
					strings.write_string(&b, key)
					strings.write_byte(&b, '}')
				}
				continue
			}
		}
		strings.write_byte(&b, c)
		i += 1
	}
	return strings.clone(strings.to_string(b), allocator)
}

@(private)
env_interp :: proc(s: string, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	i := 0
	for i < len(s) {
		if s[i] == '$' && i + 1 < len(s) && s[i + 1] == '{' {
			end := strings.index_byte(s[i:], '}')
			if end > 0 {
				key := s[i + 2 : i + end]
				v, _ := os.lookup_env(key, context.temp_allocator)
				strings.write_string(&b, v)
				i += end + 1
				continue
			}
		}
		strings.write_byte(&b, s[i])
		i += 1
	}
	return strings.to_string(b)
}

@(private)
json_str_escape :: proc(s: string, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	for i in 0 ..< len(s) {
		c := s[i]
		switch c {
		case '"':  strings.write_string(&b, `\"`)
		case '\\': strings.write_string(&b, `\\`)
		case '\n': strings.write_string(&b, `\n`)
		case '\r': strings.write_string(&b, `\r`)
		case '\t': strings.write_string(&b, `\t`)
		case:
			if c < 0x20 {
				fmt.sbprintf(&b, `\u%04x`, c)
			} else {
				strings.write_byte(&b, c)
			}
		}
	}
	return strings.to_string(b)
}

// Run one provider. Returns results or an error message; rate_limited lets
// the caller rotate to the next backend honoring retry_after.
exec_provider :: proc(
	p: ^Provider,
	args: ^Args,
	allocator := context.allocator,
) -> (results: []Result, err: string, rate_limited: bool, retry_after: int) {
	url := interp(p.url, args, context.temp_allocator)
	if p.kind == .OpenSearch {
		return exec_opensearch(url, args, allocator)
	}
	headers := make([dynamic]string, context.temp_allocator)
	for h in p.headers {
		append(&headers, interp(h, args, context.temp_allocator))
	}
	timeout := p.timeout_sec > 0 ? p.timeout_sec : constants_timeout()
	resp: nr_http.Response
	if p.method == "POST" {
		body := interp_body(p.body, args, context.temp_allocator)
		resp = nr_http.post_json(url, headers[:], body, timeout, context.temp_allocator)
	} else {
		resp = nr_http.get(url, headers[:], timeout, context.temp_allocator)
	}
	if !resp.ok {
		return nil, strings.clone(resp.err, allocator), false, 0
	}
	if resp.status == 429 {
		return nil, strings.clone("rate limited", allocator), true, resp.retry_after
	}
	if resp.status >= 400 {
		return nil, fmt.aprintf("http %d", resp.status, allocator = allocator), false, 0
	}
	res, perr := parse_results(p, resp.body, args.limit, allocator)
	if len(res) == 0 && perr == "" {
		perr = strings.clone("no results", allocator)
	}
	return res, perr, false, 0
}

@(private)
constants_timeout :: proc() -> int {
	return 15
}

// results_path selects the items array; empty path means parse RSS/Atom.
@(private)
parse_results :: proc(
	p: ^Provider,
	body: string,
	limit: int,
	allocator := context.allocator,
) -> ([]Result, string) {
	if len(p.results_path) == 0 {
		if looks_like_xml(body) {
			return parse_feed(body, limit, p.id, allocator), ""
		}
		return nil, strings.clone("unrecognized response format", allocator)
	}
	doc, perr := json.parse_string(body, .JSON, allocator = context.temp_allocator)
	if perr != nil {
		// Some providers can be coerced to emit feeds; try XML too.
		if looks_like_xml(body) {
			return parse_feed(body, limit, p.id, allocator), ""
		}
		return nil, fmt.aprintf("invalid json: %v", perr, allocator = allocator)
	}
	items_v := json_path(doc, p.results_path)
	items, is_arr := items_v.(json.Array)
	if !is_arr {
		return nil, strings.clone(fmt.aprintf("results_path %q not an array", p.results_path, allocator = allocator), allocator)
	}
	out := make([dynamic]Result, 0, allocator)
	for item in items {
		if len(out) >= limit {
			break
		}
		r := Result{provider = p.id}
		r.title = map_field(item, p.map_title, allocator)
		r.url = map_field(item, p.map_url, allocator)
		r.snippet = map_field(item, p.map_snippet, allocator)
		r.engine = map_field(item, p.map_engine, allocator)
		r.date = map_field(item, p.map_date, allocator)
		if sv := map_field(item, p.map_score, context.temp_allocator); len(sv) > 0 {
			f, _ := strconv.parse_f64(sv)
			r.score = f
		}
		if len(r.url) == 0 && len(r.title) == 0 {
			continue
		}
		append(&out, r)
	}
	return out[:], ""
}

// Map value is a dotted path (title, data.0.text) or a template with
// {dotted.path} placeholders resolved inside the item object.
@(private)
map_field :: proc(item: json.Value, spec: string, allocator := context.allocator) -> string {
	if len(spec) == 0 {
		return ""
	}
	if strings.contains(spec, "{") {
		b := strings.builder_make(allocator)
		i := 0
		for i < len(spec) {
			if spec[i] == '{' {
				end := strings.index_byte(spec[i:], '}')
				if end > 0 {
					key := spec[i + 1 : i + end]
					strings.write_string(&b, json_as_string(json_path(item, key), context.temp_allocator))
					i += end + 1
					continue
				}
			}
			strings.write_byte(&b, spec[i])
			i += 1
		}
		return strings.to_string(b)
	}
	return json_as_string(json_path(item, spec), allocator)
}

@(private)
json_path :: proc(v: json.Value, path: string) -> json.Value {
	cur := v
	for part in strings.split(path, ".", context.temp_allocator) {
		#partial switch c in cur {
		case json.Object:
			next, ok := c[part]
			if !ok {
				return nil
			}
			cur = next
		case json.Array:
			idx, ok := strconv.parse_int(part)
			if !ok || idx < 0 || idx >= len(c) {
				return nil
			}
			cur = c[idx]
		case:
			return nil
		}
	}
	return cur
}

@(private)
json_as_string :: proc(v: json.Value, allocator := context.allocator) -> string {
	#partial switch c in v {
	case string:
		return strings.clone(c, allocator)
	case f64:
		return fmt.aprintf("%g", c, allocator = allocator)
	case i64:
		return fmt.aprintf("%d", c, allocator = allocator)
	case bool:
		return strings.clone(c ? "true" : "false", allocator)
	}
	return ""
}

@(private)
looks_like_xml :: proc(body: string) -> bool {
	t := strings.trim_space(body)
	return strings.has_prefix(t, "<?xml") || strings.has_prefix(t, "<rss") || strings.has_prefix(t, "<feed")
}

// Fetch-kind providers return a single body string (FlareSolverr emits
// rendered HTML at solution.response). {url} substitutes the target.
exec_fetch :: proc(
	p: ^Provider,
	target_url: string,
	allocator := context.allocator,
) -> (body: string, err: string) {
	url := interp(p.url, &Args{url = target_url}, context.temp_allocator)
	headers := make([dynamic]string, context.temp_allocator)
	for h in p.headers {
		append(&headers, interp(h, &Args{url = target_url}, context.temp_allocator))
	}
	timeout := p.timeout_sec > 0 ? p.timeout_sec : 60
	resp: nr_http.Response
	if p.method == "POST" {
		b := interp_body(p.body, &Args{url = target_url}, context.temp_allocator)
		resp = nr_http.post_json(url, headers[:], b, timeout, context.temp_allocator)
	} else {
		resp = nr_http.get(url, headers[:], timeout, context.temp_allocator)
	}
	if !resp.ok {
		return "", strings.clone(resp.err, allocator)
	}
	if resp.status >= 400 {
		return "", fmt.aprintf("http %d", resp.status, allocator = allocator)
	}
	if len(p.results_path) > 0 {
		doc, perr := json.parse_string(resp.body, .JSON, allocator = context.temp_allocator)
		if perr != nil {
			return "", fmt.aprintf("invalid json: %v", perr, allocator = allocator)
		}
		v := json_path(doc, p.results_path)
		if s, ok := v.(string); ok {
			return strings.clone(s, allocator), ""
		}
		return "", "response had no body at results_path"
	}
	return strings.clone(resp.body, allocator), ""
}

// Look up a fetch-kind provider by id (via=...) honoring readiness.
fetch_provider_by_id :: proc(id: string, allocator := context.allocator) -> (Provider, bool) {
	for &p in load_providers(allocator) {
		if p.id == id && p.kind == .Fetch && provider_ready(&p) {
			return p, true
		}
	}
	return {}, false
}


@(private)
valid_placeholder :: proc(key: string) -> bool {
	if len(key) == 0 || len(key) > 16 {
		return false
	}
	for i in 0 ..< len(key) {
		c := key[i]
		switch c {
		case 'a' ..= 'z', '0' ..= '9', '_', '?':
		case:
			return false
		}
	}
	return true
}
