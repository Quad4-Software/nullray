// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
fetch_rss tool: download an RSS/Atom feed and return a plain digest.
*/

package tools

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "nullray:constants"
import nr_http "nullray:http"
import nr_search "nullray:search"

tool_fetch_rss :: proc(args_json: string, allocator := context.allocator) -> (string, string) {
	url, err := json_arg_string(args_json, "url", allocator)
	if err != "" {
		return "", err
	}
	defer delete(url)
	if block, why := fetch_url_blocked(url); block {
		return "", strings.clone(why, allocator)
	}
	count, _ := json_arg_int_optional(args_json, "count", RSS_DEFAULT_ITEMS, allocator)
	if count <= 0 {
		count = RSS_DEFAULT_ITEMS
	}
	if count > RSS_MAX_ITEMS {
		count = RSS_MAX_ITEMS
	}
	max_bytes := constants.DEFAULT_FETCH_MAX_BYTES
	if raw, ok := os.lookup_env(constants.ENV_FETCH_MAX_BYTES, context.temp_allocator); ok {
		if n, parsed := strconv.parse_int(strings.trim_space(raw)); parsed && n > 0 {
			max_bytes = n
		}
	}
	headers := []string{
		"Accept: application/rss+xml, application/atom+xml, application/xml;q=0.9, text/xml;q=0.8, */*;q=0.1",
		"User-Agent: nullray-fetch/1.0",
	}
	// Reuse soft-redirect following from fetch_url via get_checked loop.
	cur := strings.clone(url, context.temp_allocator)
	final_url := cur
	resp: nr_http.Response
	seen := make([dynamic]string, 0, HTML_SOFT_REDIRECT_MAX + 1, context.temp_allocator)
	append(&seen, cur)
	for hop in 0 ..= HTML_SOFT_REDIRECT_MAX {
		resp = nr_http.get_checked(cur, headers, 30, fetch_url_allow_hop, context.temp_allocator)
		if !resp.ok {
			break
		}
		final_url = cur
		body_probe := resp.body
		if len(body_probe) > max_bytes {
			body_probe = body_probe[:max_bytes]
		}
		if resp.status == 200 && hop < HTML_SOFT_REDIRECT_MAX && len(body_probe) < 4096 {
			if next, nok := html_soft_redirect_target(cur, body_probe, context.temp_allocator); nok {
				if block, why := fetch_url_blocked(next); block {
					return "", fmt.aprintf("soft redirect blocked: %s", why, allocator = allocator)
				}
				if next == cur {
					break
				}
				cycled := false
				for s in seen {
					if s == next {
						cycled = true
						break
					}
				}
				if cycled {
					break
				}
				append(&seen, next)
				cur = next
				continue
			}
		}
		break
	}
	if !resp.ok || resp.status == 403 || resp.status == 503 {
		if p, ok := nr_search.fetch_provider_by_id("flaresolverr", context.temp_allocator); ok {
			if fb, ferr := nr_search.exec_fetch(&p, final_url, context.temp_allocator); ferr == "" {
				resp.ok = true
				resp.status = 200
				resp.body = fb
			}
		}
	}
	if !resp.ok {
		detail := resp.err
		if len(detail) == 0 {
			detail = fmt.tprintf("HTTP %d", resp.status)
		}
		return "", fmt.aprintf("fetch_rss failed: %s", detail, allocator = allocator)
	}
	if resp.status >= 400 {
		return "", fmt.aprintf("fetch_rss failed: HTTP %d from %s", resp.status, final_url, allocator = allocator)
	}
	body := resp.body
	if len(body) > max_bytes {
		body = body[:max_bytes]
	}
	if !rss_looks_like(body) {
		// Helpful nudge when the URL is a normal HTML page.
		hint := ""
		if html_looks_like(body) {
			hint = " (looks like HTML; use fetch_url for pages, or point at the site's /feed|/rss|/atom.xml)"
		}
		return "", fmt.aprintf("not an RSS/Atom feed at %s%s", final_url, hint, allocator = allocator)
	}
	feed, ok := rss_parse(body, count, context.temp_allocator)
	if !ok {
		return "", fmt.aprintf("failed to parse feed at %s", final_url, allocator = allocator)
	}
	out := rss_format(feed, final_url, allocator)
	return out, ""
}
