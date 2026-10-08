// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Detect browser-style soft redirects in HTML bodies.

GitHub Pages versioned docs often return 200 with meta refresh or
window.location.replace("latest/") instead of an HTTP 3xx. fetch_url
follows those so agents get the real page text.
*/

package tools

import "core:fmt"
import "core:strings"

HTML_SOFT_REDIRECT_MAX :: 5

// Absolute http(s) URL for a relative or absolute location against base_url.
html_resolve_url :: proc(base_url, location: string, allocator := context.temp_allocator) -> (url: string, ok: bool) {
	loc := strings.trim_space(location)
	if len(loc) == 0 {
		return "", false
	}
	// Strip surrounding quotes leftover from attribute parsers.
	if len(loc) >= 2 {
		q0, q1 := loc[0], loc[len(loc) - 1]
		if (q0 == '"' && q1 == '"') || (q0 == '\'' && q1 == '\'') {
			loc = loc[1:len(loc) - 1]
		}
	}
	lower := strings.to_lower(loc, context.temp_allocator)
	if strings.has_prefix(lower, "javascript:") || strings.has_prefix(lower, "data:") || strings.has_prefix(lower, "file:") {
		return "", false
	}
	if strings.has_prefix(lower, "http://") || strings.has_prefix(lower, "https://") {
		return strings.clone(loc, allocator), true
	}
	scheme, host, path, ok_base := html_split_base(base_url)
	if !ok_base {
		return "", false
	}
	if strings.has_prefix(loc, "//") {
		return fmt.aprintf("%s:%s", scheme, loc, allocator = allocator), true
	}
	if strings.has_prefix(loc, "/") {
		return fmt.aprintf("%s://%s%s", scheme, host, loc, allocator = allocator), true
	}
	dir := path
	if len(dir) == 0 {
		dir = "/"
	}
	if i := strings.last_index_byte(dir, '/'); i >= 0 {
		dir = dir[:i + 1]
	} else {
		dir = "/"
	}
	return fmt.aprintf("%s://%s%s%s", scheme, host, dir, loc, allocator = allocator), true
}

// Minimal scheme/host/path split so tools does not depend on private http API.
@(private)
html_split_base :: proc(base_url: string) -> (scheme, host, path: string, ok: bool) {
	raw := strings.trim_space(base_url)
	lower := strings.to_lower(raw, context.temp_allocator)
	rest := raw
	if strings.has_prefix(lower, "https://") {
		scheme = "https"
		rest = raw[8:]
	} else if strings.has_prefix(lower, "http://") {
		scheme = "http"
		rest = raw[7:]
	} else {
		return "", "", "", false
	}
	slash := strings.index_byte(rest, '/')
	if slash < 0 {
		host = rest
		path = "/"
	} else {
		host = rest[:slash]
		path = rest[slash:]
	}
	if len(host) == 0 {
		return "", "", "", false
	}
	// Drop query/fragment from path for relative joins.
	if q := strings.index_byte(path, '?'); q >= 0 {
		path = path[:q]
	}
	if h := strings.index_byte(path, '#'); h >= 0 {
		path = path[:h]
	}
	return scheme, host, path, true
}

@(private)
html_attr_value :: proc(tag, name: string) -> (val: string, ok: bool) {
	lower_tag := strings.to_lower(tag, context.temp_allocator)
	needle := strings.to_lower(name, context.temp_allocator)
	idx := strings.index(lower_tag, needle)
	if idx < 0 {
		return "", false
	}
	rest := tag[idx + len(name):]
	rest = strings.trim_left_space(rest)
	if len(rest) == 0 || rest[0] != '=' {
		return "", false
	}
	rest = strings.trim_left_space(rest[1:])
	if len(rest) == 0 {
		return "", false
	}
	if rest[0] == '"' || rest[0] == '\'' {
		q := rest[0]
		rest = rest[1:]
		end := strings.index_byte(rest, q)
		if end < 0 {
			return "", false
		}
		return rest[:end], true
	}
	// Unquoted: stop at whitespace or >
	end := 0
	for end < len(rest) {
		c := rest[end]
		if c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '>' {
			break
		}
		end += 1
	}
	return rest[:end], true
}

// Parse meta http-equiv=refresh content="N; url=..."
@(private)
html_meta_refresh_url :: proc(html: string) -> (url: string, ok: bool) {
	lower := strings.to_lower(html, context.temp_allocator)
	search := lower
	offset := 0
	for {
		idx := strings.index(search, "<meta")
		if idx < 0 {
			return "", false
		}
		abs := offset + idx
		rest := html[abs:]
		end := strings.index_byte(rest, '>')
		if end < 0 {
			return "", false
		}
		tag := rest[:end]
		tag_l := strings.to_lower(tag, context.temp_allocator)
		if strings.contains(tag_l, "http-equiv") && strings.contains(tag_l, "refresh") {
			content, cok := html_attr_value(tag, "content")
			if !cok {
				return "", false
			}
			// content may be "1;url=path" or "0; URL='path'"
			c_l := strings.to_lower(content, context.temp_allocator)
			uidx := strings.index(c_l, "url=")
			if uidx < 0 {
				return "", false
			}
			target := strings.trim_space(content[uidx + 4:])
			return target, len(target) > 0
		}
		offset = abs + end + 1
		if offset >= len(html) {
			return "", false
		}
		search = lower[offset:]
	}
}

// Best-effort parse of window.location.replace("...") or location.href = "..."
@(private)
html_js_location_url :: proc(html: string) -> (url: string, ok: bool) {
	patterns := []string{
		"window.location.replace(",
		"location.replace(",
		"window.location.href=",
		"location.href=",
		"window.location.assign(",
		"location.assign(",
	}
	lower := strings.to_lower(html, context.temp_allocator)
	best_pos := len(html) + 1
	best := ""
	for p in patterns {
		idx := strings.index(lower, p)
		if idx < 0 {
			continue
		}
		if idx >= best_pos {
			continue
		}
		rest := html[idx + len(p):]
		rest = strings.trim_left_space(rest)
		if len(rest) == 0 {
			continue
		}
		// skip optional (
		if rest[0] == '(' {
			rest = strings.trim_left_space(rest[1:])
		}
		if len(rest) == 0 {
			continue
		}
		if rest[0] != '"' && rest[0] != '\'' {
			continue
		}
		q := rest[0]
		rest = rest[1:]
		end := strings.index_byte(rest, q)
		if end <= 0 {
			continue
		}
		best = rest[:end]
		best_pos = idx
	}
	if len(best) == 0 {
		return "", false
	}
	return best, true
}

// Extract a soft-redirect target from a 200 HTML body, if any.
html_soft_redirect_target :: proc(base_url, body: string, allocator := context.temp_allocator) -> (url: string, ok: bool) {
	if !html_looks_like(body) {
		return "", false
	}
	// Prefer meta refresh (more standard) over JS location.
	if t, tok := html_meta_refresh_url(body); tok {
		if abs, aok := html_resolve_url(base_url, t, allocator); aok {
			return abs, true
		}
	}
	if t, tok := html_js_location_url(body); tok {
		if abs, aok := html_resolve_url(base_url, t, allocator); aok {
			return abs, true
		}
	}
	return "", false
}
