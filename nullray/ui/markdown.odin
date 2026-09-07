/*
Parse markdown-ish assistant text into blocks for terminal rendering.

Block lang and body fields are slices into the source string passed to md_parse.
The source string must outlive the returned blocks.
*/

package ui

import "core:strings"
import "core:unicode"
import "core:unicode/utf8"

Md_Kind :: enum {
	Text,
	Heading,
	Quote,
	List_Item,
	Code,
	Hr,
	Blank,
}

Md_Block :: struct {
	kind:     Md_Kind,
	level:    int,
	lang:     string,
	body:     string,
	fence_id: int,
}

md_plain_fallback :: proc(src: string, allocator := context.temp_allocator) -> []Md_Block {
	if len(strings.trim_space(src)) == 0 {
		return nil
	}
	blocks: [dynamic]Md_Block
	blocks.allocator = allocator
	append(&blocks, Md_Block{kind = .Text, body = src, fence_id = -1})
	return blocks[:]
}

md_parse :: proc(src: string, allocator := context.temp_allocator) -> []Md_Block {
	if len(src) == 0 {
		return nil
	}

	blocks: [dynamic]Md_Block
	blocks.allocator = allocator

	para_start: int
	para_end: int
	para_has: bool
	in_fence := false
	fence_id := 0
	fence_lang: string
	fence_body_start: int
	next_fence_id := 0

	i := 0
	guard := 0
	max_guard := len(src) + 8
	for i < len(src) {
		guard += 1
		if guard > max_guard {
			break
		}
		line_start := i
		line_end := i
		for line_end < len(src) && src[line_end] != '\n' {
			line_end += 1
		}
		line := src[line_start:line_end]
		advance := line_end - line_start
		if line_end < len(src) {
			advance += 1
		}
		if advance <= 0 {
			break
		}
		if len(blocks) > 4000 {
			append(&blocks, Md_Block{kind = .Text, body = src[i:], fence_id = -1})
			break
		}

		if in_fence {
			if md_is_fence_close(line) {
				body := src[fence_body_start:line_start]
				if len(body) > 0 && body[len(body) - 1] == '\n' {
					body = body[:len(body) - 1]
				}
				append(
					&blocks,
					Md_Block{
						kind = .Code,
						lang = fence_lang,
						body = body,
						fence_id = fence_id,
					},
				)
				in_fence = false
				fence_lang = ""
			}
			i += advance
			continue
		}

		trimmed := strings.trim_space(line)
		if len(trimmed) == 0 {
			md_flush_para(&blocks, src, &para_start, &para_end, &para_has)
			append(&blocks, Md_Block{kind = .Blank, fence_id = -1})
			i += advance
			continue
		}

		if md_is_hr(trimmed) {
			md_flush_para(&blocks, src, &para_start, &para_end, &para_has)
			append(&blocks, Md_Block{kind = .Hr, fence_id = -1})
			i += advance
			continue
		}

		if lang, ok := md_fence_open(trimmed); ok {
			md_flush_para(&blocks, src, &para_start, &para_end, &para_has)
			in_fence = true
			fence_id = next_fence_id
			next_fence_id += 1
			fence_lang = lang
			fence_body_start = line_end + 1
			if line_end >= len(src) {
				fence_body_start = len(src)
			}
			i += advance
			continue
		}

		if level, body, ok := md_heading(line); ok {
			md_flush_para(&blocks, src, &para_start, &para_end, &para_has)
			append(
				&blocks,
				Md_Block{kind = .Heading, level = level, body = body, fence_id = -1},
			)
			i += advance
			continue
		}

		if body, ok := md_quote(line); ok {
			md_flush_para(&blocks, src, &para_start, &para_end, &para_has)
			append(&blocks, Md_Block{kind = .Quote, body = body, fence_id = -1})
			i += advance
			continue
		}

		if indent, body, ok := md_list_item(line); ok {
			md_flush_para(&blocks, src, &para_start, &para_end, &para_has)
			append(
				&blocks,
				Md_Block{kind = .List_Item, level = indent, body = body, fence_id = -1},
			)
			i += advance
			continue
		}

		if !para_has {
			para_start = line_start
			para_has = true
		}
		para_end = line_end
		i += advance
	}

	if in_fence {
		body := src[fence_body_start:]
		append(
			&blocks,
			Md_Block{kind = .Code, lang = fence_lang, body = body, fence_id = fence_id},
		)
	}

	md_flush_para(&blocks, src, &para_start, &para_end, &para_has)
	return blocks[:]
}

@(private)
md_flush_para :: proc(
	blocks: ^[dynamic]Md_Block,
	src: string,
	para_start: ^int,
	para_end: ^int,
	para_has: ^bool,
) {
	if !para_has^ {
		return
	}
	append(blocks, Md_Block{kind = .Text, body = src[para_start^:para_end^], fence_id = -1})
	para_has^ = false
}

@(private)
md_is_fence_close :: proc(line: string) -> bool {
	trimmed := strings.trim_space(line)
	return len(trimmed) >= 3 && strings.has_prefix(trimmed, "```")
}

@(private)
md_fence_open :: proc(line: string) -> (lang: string, ok: bool) {
	trimmed := strings.trim_space(line)
	if !strings.has_prefix(trimmed, "```") {
		return "", false
	}
	rest := strings.trim_space(trimmed[3:])
	return rest, true
}

@(private)
md_is_hr :: proc(line: string) -> bool {
	if len(line) < 3 {
		return false
	}
	ch := line[0]
	if ch != '-' && ch != '*' && ch != '_' {
		return false
	}
	for i in 1 ..< len(line) {
		if line[i] != ch && !unicode.is_space(rune(line[i])) {
			return false
		}
	}
	return true
}

@(private)
md_heading :: proc(line: string) -> (level: int, body: string, ok: bool) {
	i := 0
	for i < len(line) && line[i] == '#' {
		i += 1
	}
	if i == 0 || i > 6 {
		return 0, "", false
	}
	if i < len(line) && !unicode.is_space(rune(line[i])) {
		return 0, "", false
	}
	body_start := i
	for body_start < len(line) && unicode.is_space(rune(line[body_start])) {
		body_start += 1
	}
	return i, line[body_start:], true
}

@(private)
md_quote :: proc(line: string) -> (body: string, ok: bool) {
	i := 0
	for i < len(line) && unicode.is_space(rune(line[i])) {
		i += 1
	}
	if i >= len(line) || line[i] != '>' {
		return "", false
	}
	i += 1
	if i < len(line) && line[i] == ' ' {
		i += 1
	}
	return line[i:], true
}

@(private)
md_list_item :: proc(line: string) -> (indent: int, body: string, ok: bool) {
	i := 0
	spaces := 0
	for i < len(line) {
		r, size := utf8.decode_rune_in_string(line[i:])
		if size <= 0 {
			break
		}
		if r == ' ' {
			spaces += 1
			i += size
			continue
		}
		if r == '\t' {
			spaces += 4
			i += size
			continue
		}
		break
	}
	if i >= len(line) {
		return 0, "", false
	}
	marker := line[i]
	if marker != '-' && marker != '*' && marker != '+' {
		return 0, "", false
	}
	i += 1
	if i < len(line) && line[i] == ' ' {
		i += 1
	} else if i < len(line) {
		return 0, "", false
	}
	return spaces, line[i:], true
}

word_wrap_lines :: proc(text: string, width: int, allocator := context.temp_allocator) -> []string {
	if width <= 0 {
		if len(text) == 0 {
			return nil
		}
		lines: [dynamic]string
		lines.allocator = allocator
		append(&lines, strings.clone(text, allocator))
		return lines[:]
	}
	if len(text) == 0 {
		lines: [dynamic]string
		lines.allocator = allocator
		append(&lines, strings.clone("", allocator))
		return lines[:]
	}

	buf: [dynamic]u8
	buf.allocator = allocator
	lines: [dynamic]string
	lines.allocator = allocator

	line_start := 0
	col := 0
	last_break := -1
	i := 0
	stall := 0

	for i < len(text) {
		r, size := utf8.decode_rune_in_string(text[i:])
		if size <= 0 {
			break
		}

		if r == '\n' {
			word_wrap_push_line(&lines, buf[:], line_start, len(buf))
			line_start = len(buf)
			col = 0
			last_break = -1
			stall = 0
			i += size
			continue
		}

		rw := max(1, rune_cols(r))
		if col + rw > width && col > 0 {
			prev_line_start := line_start
			if last_break > line_start {
				word_wrap_push_line(&lines, buf[:], line_start, last_break)
				line_start = last_break
				for line_start < len(buf) && buf[line_start] == ' ' {
					line_start += 1
				}
			} else {
				word_wrap_push_line(&lines, buf[:], line_start, len(buf))
				line_start = len(buf)
			}
			col = word_wrap_cols(buf[line_start:])
			last_break = -1
			if line_start == prev_line_start {
				stall += 1
				if stall > 2 {
					// Force progress to avoid a hang on pathological widths.
					for j in 0 ..< size {
						append(&buf, text[i + j])
					}
					col += rw
					i += size
					stall = 0
				}
			} else {
				stall = 0
			}
			continue
		}

		for j in 0 ..< size {
			append(&buf, text[i + j])
		}

		if unicode.is_space(r) || word_wrap_is_break_rune(r) {
			last_break = len(buf)
		}

		col += rw
		i += size
		stall = 0
	}

	if line_start < len(buf) {
		word_wrap_push_line(&lines, buf[:], line_start, len(buf))
	} else if len(lines) == 0 {
		append(&lines, string(buf[:0]))
	}

	return lines[:]
}

@(private)
word_wrap_push_line :: proc(lines: ^[dynamic]string, buf: []u8, start, end: int) {
	e := end
	for e > start && buf[e - 1] == ' ' {
		e -= 1
	}
	append(lines, string(buf[start:e]))
}

@(private)
word_wrap_cols :: proc(s: []u8) -> int {
	col := 0
	i := 0
	for i < len(s) {
		r, size := utf8.decode_rune_in_string(string(s[i:]))
		if size <= 0 {
			break
		}
		col += max(1, rune_cols(r))
		i += size
	}
	return col
}

@(private)
word_wrap_is_break_rune :: proc(r: rune) -> bool {
	switch r {
	case '.', ',', ';', ':', '!', '?', '-', '/', ')':
		return true
	}
	return false
}

// Strip paired backticks for plain measurement. Unmatched ticks are dropped.
md_strip_inline_ticks :: proc(src: string, allocator := context.temp_allocator) -> string {
	if len(src) == 0 {
		return ""
	}
	b: strings.Builder
	strings.builder_init(&b, allocator)
	in_code := false
	i := 0
	for i < len(src) {
		if src[i] == '`' {
			in_code = !in_code
			i += 1
			continue
		}
		strings.write_byte(&b, src[i])
		i += 1
	}
	return strings.to_string(b)
}

// Draw one visual line of markdown-ish text with `inline code` coloring.
// Returns columns written.
draw_inline_md_line :: proc(
	b: ^Buffer,
	x, y, width: int,
	text: string,
	fg, code_fg, bg: Color,
	style: Style = {},
) -> int {
	if width <= 0 {
		return 0
	}
	cx := 0
	in_code := false
	i := 0
	for i < len(text) {
		if text[i] == '`' {
			in_code = !in_code
			i += 1
			continue
		}
		r, size := utf8.decode_rune_in_string(text[i:])
		if size <= 0 {
			break
		}
		w := max(1, rune_cols(r))
		if cx + w > width {
			break
		}
		use_fg := fg
		use_style := style
		if in_code {
			use_fg = code_fg
			use_style += {.Bold}
		}
		buffer_put(b, x + cx, y, r, use_fg, bg, use_style)
		cx += w
		i += size
	}
	return cx
}

// Word-wrap and draw markdown text with inline ticks. Returns lines used.
draw_md_text_wrapped :: proc(
	b: ^Buffer,
	x, y, width, max_lines: int,
	text: string,
	fg, code_fg, bg: Color,
	style: Style = {},
	skip_lines: int = 0,
) -> int {
	if width <= 0 || max_lines <= 0 {
		return 0
	}
	drawn := 0
	vis := 0
	col := 0
	line_start := 0
	i := 0
	guard := 0
	max_guard := len(text) * 2 + 8

	for i <= len(text) {
		guard += 1
		if guard > max_guard {
			break
		}
		at_end := i >= len(text)
		r: rune = 0
		size := 0
		if !at_end {
			r, size = utf8.decode_rune_in_string(text[i:])
			if size <= 0 {
				break
			}
		}

		need_flush := at_end || r == '\n'
		rw := 0
		if !at_end && r != '\n' && r != '`' {
			rw = max(1, rune_cols(r))
			if col + rw > width && col > 0 {
				need_flush = true
			}
		}

		if need_flush {
			if vis >= skip_lines && drawn < max_lines {
				seg := text[line_start:i]
				_ = draw_inline_md_line(b, x, y + drawn, width, seg, fg, code_fg, bg, style)
				drawn += 1
			}
			vis += 1
			if at_end {
				break
			}
			if r == '\n' {
				i += size
				line_start = i
				col = 0
				continue
			}
			// Soft wrap: restart line at current rune
			line_start = i
			col = 0
			if drawn >= max_lines {
				break
			}
			continue
		}

		if r == '`' {
			i += size
			continue
		}
		col += rw
		i += size
	}
	return drawn
}

md_text_line_count :: proc(text: string, width: int) -> int {
	plain := md_strip_inline_ticks(text, context.temp_allocator)
	return wrap_line_count(plain, width)
}
