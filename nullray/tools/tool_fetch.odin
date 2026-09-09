// SPDX-License-Identifier: 0BSD
/*
Read-only HTTP(S) fetch with SSRF basics, size caps, and HTML readability.
*/

package tools

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "nullray:constants"
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
	resp := nr_http.get_checked(url, headers, 30, fetch_url_allow_hop, context.temp_allocator)
	if !resp.ok {
		return "", fmt.aprintf("fetch failed: %s", resp.err, allocator = allocator)
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
	out := fmt.aprintf("status=%d format=%s\n%s%s", resp.status, kind, rendered, note, allocator = allocator)
	delete(owned_render)
	return out, ""
}
