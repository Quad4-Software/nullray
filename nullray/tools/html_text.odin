// SPDX-License-Identifier: 0BSD
/*
HTML to plain text for fetch_url readability. Not a full browser.
*/

package tools

import "core:fmt"
import "core:strings"
import "core:unicode"
import "core:unicode/utf8"

html_looks_like :: proc(body: string) -> bool {
	probe := body
	if len(probe) > 4096 {
		probe = probe[:4096]
	}
	lower := strings.to_lower(probe, context.temp_allocator)
	if strings.contains(lower, "<!doctype html") || strings.contains(lower, "<html") {
		return true
	}
	if strings.contains(lower, "<head") || strings.contains(lower, "<body") {
		return true
	}
	tags := 0
	for i := 0; i + 2 < len(lower); i += 1 {
		if lower[i] == '<' {
			c := lower[i + 1]
			if (c >= 'a' && c <= 'z') || c == '/' {
				tags += 1
				if tags >= 8 {
					return true
				}
			}
		}
	}
	return false
}

html_to_readable_text :: proc(html: string, allocator := context.allocator) -> string {
	stripped := html_strip_noise(html, context.temp_allocator)
	b: strings.Builder
	strings.builder_init(&b, allocator)
	i := 0
	for i < len(stripped) {
		if stripped[i] == '<' {
			end := strings.index_byte(stripped[i:], '>')
			if end < 0 {
				break
			}
			tag := stripped[i + 1:i + end]
			tag_lower := strings.to_lower(tag, context.temp_allocator)
			name := tag_lower
			if strings.has_prefix(name, "/") {
				name = name[1:]
			}
			if sp := strings.index_any(name, " \t\r\n/"); sp >= 0 {
				name = name[:sp]
			}
			switch name {
			case "br", "p", "div", "tr", "li", "h1", "h2", "h3", "h4", "h5", "h6",
				"section", "article", "header", "footer", "nav", "pre", "blockquote",
				"table", "thead", "tbody", "hr":
				strings.write_byte(&b, '\n')
			case "td", "th":
				strings.write_byte(&b, ' ')
			}
			i += end + 1
			continue
		}
		if stripped[i] == '&' {
			ent, n := html_decode_entity(stripped[i:])
			if n > 0 {
				strings.write_string(&b, ent)
				i += n
				continue
			}
		}
		strings.write_byte(&b, stripped[i])
		i += 1
	}
	raw := strings.to_string(b)
	collapsed := html_collapse_ws(raw, allocator)
	delete(raw)
	return collapsed
}

@(private)
html_strip_noise :: proc(html: string, allocator := context.allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	lower := strings.to_lower(html, context.temp_allocator)
	i := 0
	for i < len(html) {
		if i + 6 < len(lower) &&
		   (strings.has_prefix(lower[i:], "<script") ||
			   strings.has_prefix(lower[i:], "<style") ||
			   strings.has_prefix(lower[i:], "<noscript")) {
			close: string
			if strings.has_prefix(lower[i:], "<script") {
				close = "</script>"
			} else if strings.has_prefix(lower[i:], "<style") {
				close = "</style>"
			} else {
				close = "</noscript>"
			}
			rest := lower[i:]
			j := strings.index(rest, close)
			if j < 0 {
				break
			}
			i += j + len(close)
			continue
		}
		if i + 3 < len(lower) && strings.has_prefix(lower[i:], "<!--") {
			rest := lower[i:]
			j := strings.index(rest, "-->")
			if j < 0 {
				break
			}
			i += j + 3
			continue
		}
		strings.write_byte(&b, html[i])
		i += 1
	}
	return strings.to_string(b)
}

@(private)
html_decode_entity :: proc(s: string) -> (out: string, n: int) {
	if len(s) < 3 || s[0] != '&' {
		return "", 0
	}
	semi := strings.index_byte(s, ';')
	if semi < 2 || semi > 32 {
		return "", 0
	}
	body := s[1:semi]
	switch body {
	case "amp":
		return "&", semi + 1
	case "lt":
		return "<", semi + 1
	case "gt":
		return ">", semi + 1
	case "quot":
		return "\"", semi + 1
	case "apos", "#39":
		return "'", semi + 1
	case "nbsp":
		return " ", semi + 1
	case "mdash", "ndash":
		return "-", semi + 1
	}
	if strings.has_prefix(body, "#x") || strings.has_prefix(body, "#X") {
		hex := body[2:]
		val: int = 0
		for i in 0 ..< len(hex) {
			c := hex[i]
			d: int
			switch c {
			case '0' ..= '9':
				d = int(c - '0')
			case 'a' ..= 'f':
				d = int(c - 'a' + 10)
			case 'A' ..= 'F':
				d = int(c - 'A' + 10)
			case:
				return "", 0
			}
			val = (val << 4) + d
			if val > 0x10FFFF {
				return "", 0
			}
		}
		return fmt.tprintf("%r", rune(val)), semi + 1
	}
	if strings.has_prefix(body, "#") {
		digits := body[1:]
		if len(digits) == 0 {
			return "", 0
		}
		val: int = 0
		for i in 0 ..< len(digits) {
			c := digits[i]
			if c < '0' || c > '9' {
				return "", 0
			}
			val = val * 10 + int(c - '0')
			if val > 0x10FFFF {
				return "", 0
			}
		}
		return fmt.tprintf("%r", rune(val)), semi + 1
	}
	return "", 0
}

@(private)
html_collapse_ws :: proc(s: string, allocator := context.allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	prev_space := false
	prev_nl := false
	i := 0
	for i < len(s) {
		r, width := utf8.decode_rune_in_string(s[i:])
		if width <= 0 {
			break
		}
		i += width
		if r == '\r' {
			continue
		}
		if r == '\n' {
			if !prev_nl {
				strings.write_byte(&b, '\n')
				prev_nl = true
			}
			prev_space = true
			continue
		}
		if unicode.is_space(r) {
			if !prev_space {
				strings.write_byte(&b, ' ')
				prev_space = true
			}
			prev_nl = false
			continue
		}
		strings.write_string(&b, fmt.tprintf("%r", r))
		prev_space = false
		prev_nl = false
	}
	out := strings.to_string(b)
	trimmed := strings.trim_space(out)
	if len(trimmed) == len(out) {
		return out
	}
	cloned := strings.clone(trimmed, allocator)
	delete(out)
	return cloned
}
