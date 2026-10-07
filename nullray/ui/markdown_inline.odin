// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Flatten inline markdown into display text plus a per-byte style kind.

Supported markers: `code`, **bold**, __bold__, *italic*, _italic_,
~~strike~~, [text](url) rendered as "text (url)", and bare http(s)
links. Unmatched markers stay literal. Backslash escapes the next
marker character.
*/

package ui

import "core:strings"
import "core:unicode/utf8"

Md_Inline_Kind :: enum u8 {
	Normal,
	Bold,
	Italic,
	Strike,
	Code,
	Link,
	Link_Url,
}

Md_Flat :: struct {
	text:  string,
	kinds: []Md_Inline_Kind,
}

// Display text with every inline marker stripped and links expanded.
md_inline_plain :: proc(src: string, allocator := context.temp_allocator) -> string {
	return md_inline_flatten(src, allocator).text
}

md_inline_flatten :: proc(src: string, allocator := context.temp_allocator) -> Md_Flat {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	kinds := make([dynamic]Md_Inline_Kind, 0, len(src) + 8, allocator)

	i := 0
	for i < len(src) {
		c := src[i]
		if c == '\\' && i + 1 < len(src) && md_is_escapable(src[i + 1]) {
			_, size := utf8.decode_rune_in_string(src[i + 1:])
			md_emit(&b, &kinds, src[i + 1:i + 1 + size], .Normal)
			i += 1 + size
			continue
		}
		if c == '`' {
			if end := strings.index_byte(src[i + 1:], '`'); end > 0 {
				md_emit(&b, &kinds, src[i + 1:i + 1 + end], .Code)
				i += end + 2
				continue
			}
		}
		if c == '~' && i + 1 < len(src) && src[i + 1] == '~' {
			if end := strings.index(src[i + 2:], "~~"); end > 0 {
				md_emit(&b, &kinds, src[i + 2:i + 2 + end], .Strike)
				i += end + 4
				continue
			}
		}
		if c == '*' || c == '_' {
			if next, ok := md_emit_emph(&b, &kinds, src, i); ok {
				i = next
				continue
			}
		}
		if c == '[' {
			if next, ok := md_emit_link(&b, &kinds, src, i); ok {
				i = next
				continue
			}
		}
		if c == 'h' {
			if url, ok := md_bare_url(src, i); ok {
				md_emit(&b, &kinds, url, .Link)
				i += len(url)
				continue
			}
		}
		_, size := utf8.decode_rune_in_string(src[i:])
		if size <= 0 {
			break
		}
		md_emit(&b, &kinds, src[i:i + size], .Normal)
		i += size
	}
	return Md_Flat{text = strings.to_string(b), kinds = kinds[:]}
}

@(private)
md_emit :: proc(b: ^strings.Builder, kinds: ^[dynamic]Md_Inline_Kind, s: string, kind: Md_Inline_Kind) {
	strings.write_string(b, s)
	for _ in 0 ..< len(s) {
		append(kinds, kind)
	}
}

// Emphasis opener must sit on a word boundary so snake_case and 2*3
// stay literal. The closer just needs a non-space before it.
@(private)
md_emit_emph :: proc(
	b: ^strings.Builder,
	kinds: ^[dynamic]Md_Inline_Kind,
	src: string,
	i: int,
) -> (next: int, ok: bool) {
	if i > 0 && md_ident_byte(src[i - 1]) {
		return i, false
	}
	c := src[i]
	mark_len := 1
	if i + 1 < len(src) && src[i + 1] == c {
		mark_len = 2
	}
	if i + mark_len >= len(src) || src[i + mark_len] == ' ' {
		return i, false
	}
	mark := src[i:i + mark_len]
	end := -1
	j := i + mark_len
	for j < len(src) {
		idx := strings.index(src[j:], mark)
		if idx < 0 {
			break
		}
		cand := j + idx
		if src[cand - 1] != ' ' {
			end = cand
			break
		}
		j = cand + 1
	}
	if end < 0 {
		return i, false
	}
	kind := Md_Inline_Kind.Italic
	if mark_len == 2 {
		kind = .Bold
	}
	md_emit(b, kinds, src[i + mark_len:end], kind)
	return end + mark_len, true
}

@(private)
md_emit_link :: proc(
	b: ^strings.Builder,
	kinds: ^[dynamic]Md_Inline_Kind,
	src: string,
	i: int,
) -> (next: int, ok: bool) {
	rel := strings.index_byte(src[i + 1:], ']')
	if rel <= 0 {
		return i, false
	}
	close := i + 1 + rel
	if close + 1 >= len(src) || src[close + 1] != '(' {
		return i, false
	}
	rel = strings.index_byte(src[close + 2:], ')')
	if rel <= 0 {
		return i, false
	}
	end := close + 2 + rel
	text := src[i + 1:close]
	url := src[close + 2:end]
	md_emit(b, kinds, text, .Link)
	md_emit(b, kinds, " (", .Link_Url)
	md_emit(b, kinds, url, .Link_Url)
	md_emit(b, kinds, ")", .Link_Url)
	return end + 1, true
}

@(private)
md_bare_url :: proc(src: string, i: int) -> (url: string, ok: bool) {
	rest := src[i:]
	if !strings.has_prefix(rest, "http://") && !strings.has_prefix(rest, "https://") {
		return "", false
	}
	end := i + 7
	if rest[4] == 's' {
		end = i + 8
	}
	for end < len(src) && md_url_byte(src[end]) {
		end += 1
	}
	return src[i:end], true
}

@(private)
md_url_byte :: proc(c: u8) -> bool {
	switch c {
	case ' ', '\t', '\n', '\r', ')', ']', '>', '"', '\'', '<', '`':
		return false
	}
	return true
}

@(private)
md_ident_byte :: proc(c: u8) -> bool {
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_'
}

@(private)
md_is_escapable :: proc(c: u8) -> bool {
	switch c {
	case '\\', '`', '*', '_', '~', '[', ']', '(', ')', '#', '!':
		return true
	}
	return false
}
