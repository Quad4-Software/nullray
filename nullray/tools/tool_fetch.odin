// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Read-only HTTP(S) fetch with SSRF basics, size caps, and HTML readability.
*/

package tools

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "nullray:constants"
import nr_search "nullray:search"
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
	via, verr := json_arg_string_optional(args_json, "via", "", allocator)
	if verr != "" {
		return "", verr
	}
	defer delete(via)
	format, ferr := json_arg_string_optional(args_json, "format", "auto", allocator)
	if ferr != "" {
		return "", ferr
	}
	defer delete(format)
	max_chars, merr := json_arg_int_optional(args_json, "max_chars", constants.MAX_MAN_PAGE_CHARS, allocator)
	if merr != "" {
		return "", merr
	}
	if max_chars <= 0 {
		max_chars = constants.MAX_MAN_PAGE_CHARS
	}
	max_bytes := constants.DEFAULT_FETCH_MAX_BYTES
	if raw, ok := os.lookup_env(constants.ENV_FETCH_MAX_BYTES, context.temp_allocator); ok {
		if n, parsed := strconv.parse_int(strings.trim_space(raw)); parsed && n > 0 {
			max_bytes = n
		}
	}
	headers := []string{
		"Accept: text/markdown, text/plain;q=0.9, text/html;q=0.8, application/xhtml+xml;q=0.7, */*;q=0.1",
		"User-Agent: nullray-fetch/1.0",
	}
	via_err: string
	resp: nr_http.Response
	final_url := url
	if len(via) > 0 {
		// Explicit via= routes the request through the named fetch
		// provider instead of the direct path.
		p, ok := nr_search.fetch_provider_by_id(via, context.temp_allocator)
		if !ok {
			return "", fmt.aprintf("via %s: provider not found or not configured", via, allocator = allocator)
		}
		fb, ferr := nr_search.exec_fetch(&p, url, context.temp_allocator)
		if ferr != "" {
			return "", fmt.aprintf("via %s: %s", via, ferr, allocator = allocator)
		}
		resp.ok = true
		resp.status = 200
		resp.body = fb
	} else {
		cur := strings.clone(url, context.temp_allocator)
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
			// Soft redirects only apply to short HTML 200 shells (meta refresh
			// / window.location). Large pages are returned as-is.
			if resp.status == 200 && hop < HTML_SOFT_REDIRECT_MAX && len(body_probe) < 4096 {
				if next, nok := html_soft_redirect_target(cur, body_probe, context.temp_allocator); nok {
					if block, why := fetch_url_blocked(next); block {
						return "", fmt.aprintf("soft redirect blocked: %s", why, allocator = allocator)
					}
					if next == cur {
						break
					}
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
				} else {
					via_err = fmt.aprintf(" (flaresolverr failed: %s)", ferr, allocator = context.temp_allocator)
				}
			}
		}
	}
	if !resp.ok {
		detail := resp.err
		if len(detail) == 0 {
			detail = fmt.tprintf("HTTP %d", resp.status)
		}
		return "", fmt.aprintf("fetch failed: %s%s", detail, via_err, allocator = allocator)
	}
	if resp.status >= 400 {
		return "", fmt.aprintf(
			"fetch failed: HTTP %d from %s%s",
			resp.status,
			final_url,
			via_err,
			allocator = allocator,
		)
	}
	body := resp.body
	if len(body) > max_bytes {
		body = body[:max_bytes]
	}
	fmt_mode := strings.to_lower(strings.trim_space(format), context.temp_allocator)
	rendered := body
	kind := "text"
	owned_render: string
	switch fmt_mode {
	case "raw":
		kind = "raw"
	case "text":
		if html_looks_like(body) {
			owned_render = html_to_readable_text(body, allocator)
			rendered = owned_render
			kind = "html"
		}
	case "auto", "":
		if html_looks_like(body) {
			owned_render = html_to_readable_text(body, allocator)
			rendered = owned_render
			kind = "html"
		}
	case:
		return "", strings.clone("format must be auto, text, or raw", allocator)
	}
	truncated := false
	if len(rendered) > max_chars {
		head := strings.clone(rendered[:max_chars], allocator)
		if len(owned_render) > 0 {
			delete(owned_render)
		}
		rendered = head
		owned_render = head
		truncated = true
	} else if len(owned_render) == 0 {
		owned_render = strings.clone(rendered, allocator)
		rendered = owned_render
	}
	note := ""
	if truncated {
		note = fmt.tprintf("\n\n[truncated at %d chars; raise max_chars or fetch a smaller page]", max_chars)
	}
	// Always report the final URL so soft redirects are visible to the agent.
	out := fmt.aprintf(
		"status=%d format=%s url=%s\n%s%s",
		resp.status,
		kind,
		final_url,
		rendered,
		note,
		allocator = allocator,
	)
	delete(owned_render)
	return out, ""
}
