// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package ui

import "core:strings"
import "core:testing"

@(test)
test_md_parse_code_fence :: proc(t: ^testing.T) {
	src := strings.trim_space("# Title\n\nhello\n\n" + "```odin\nx := 1\n```\n\nafter")

	blocks := md_parse(src, context.temp_allocator)
	testing.expect(t, len(blocks) >= 5)

	found_code := false
	for b in blocks {
		if b.kind == .Code {
			found_code = true
			testing.expect_value(t, b.fence_id, 0)
			testing.expect(t, strings.has_prefix(b.lang, "odin"))
			testing.expect(t, strings.contains(b.body, "x := 1"))
		}
	}
	testing.expect(t, found_code)
}

@(test)
test_md_parse_fence_id_increments :: proc(t: ^testing.T) {
	src := strings.trim_space("```a\none\n```\n\n```b\ntwo\n```")

	blocks := md_parse(src, context.temp_allocator)
	id0 := -1
	id1 := -1
	for b in blocks {
		if b.kind != .Code {
			continue
		}
		if strings.contains(b.body, "one") {
			id0 = b.fence_id
		}
		if strings.contains(b.body, "two") {
			id1 = b.fence_id
		}
	}
	testing.expect_value(t, id0, 0)
	testing.expect_value(t, id1, 1)
}

@(test)
test_md_plain_fallback :: proc(t: ^testing.T) {
	src := "plain text"
	blocks := md_plain_fallback(src)
	testing.expect_value(t, len(blocks), 1)
	testing.expect_value(t, blocks[0].kind, Md_Kind.Text)
	testing.expect_value(t, blocks[0].body, src)
}

@(test)
test_word_wrap_lines_spaces :: proc(t: ^testing.T) {
	lines := word_wrap_lines("hello world foo", 8, context.temp_allocator)
	testing.expect(t, len(lines) >= 2)
	testing.expect_value(t, lines[0], "hello")
	testing.expect_value(t, lines[1], "world")
}

@(test)
test_word_wrap_lines_long_token :: proc(t: ^testing.T) {
	lines := word_wrap_lines("abcdefghij", 5, context.temp_allocator)
	testing.expect(t, len(lines) >= 2)
	testing.expect_value(t, lines[0], "abcde")
	testing.expect_value(t, lines[1], "fghij")
}

@(test)
test_word_wrap_lines_max_cap :: proc(t: ^testing.T) {
	src := "one two three four five six seven eight nine ten"
	capped := word_wrap_lines(src, 8, context.temp_allocator, 3)
	testing.expect_value(t, len(capped), 3)
	full := word_wrap_lines(src, 8, context.temp_allocator)
	testing.expect(t, len(full) > 3)
}

@(test)
test_md_parse_heading_and_list :: proc(t: ^testing.T) {
	src := strings.trim_space("## Section\n\n- item one\n> quoted")

	blocks := md_parse(src, context.temp_allocator)
	has_heading := false
	has_list := false
	has_quote := false
	for b in blocks {
	#partial switch b.kind {
		case .Heading:
			has_heading = true
			testing.expect_value(t, b.level, 2)
			testing.expect_value(t, b.body, "Section")
		case .List_Item:
			has_list = true
			testing.expect_value(t, b.body, "item one")
		case .Quote:
			has_quote = true
			testing.expect_value(t, b.body, "quoted")
		}
	}
	testing.expect(t, has_heading)
	testing.expect(t, has_list)
	testing.expect(t, has_quote)
}

@(test)
test_md_parse_hr :: proc(t: ^testing.T) {
	blocks := md_parse("above\n\n---\n\nbelow", context.temp_allocator)
	has_hr := false
	for b in blocks {
		if b.kind == .Hr {
			has_hr = true
		}
	}
	testing.expect(t, has_hr)
}

@(test)
test_md_parse_ordered_list :: proc(t: ^testing.T) {
	blocks := md_parse("1. one\n2. two\n10. ten", context.temp_allocator)
	n := 0
	for b in blocks {
		if b.kind != .List_Item {
			continue
		}
		n += 1
		if strings.contains(b.body, "two") {
			testing.expect_value(t, b.marker, "2.")
		}
		if strings.contains(b.body, "ten") {
			testing.expect_value(t, b.marker, "10.")
		}
	}
	testing.expect_value(t, n, 3)
}

@(test)
test_md_parse_nested_list :: proc(t: ^testing.T) {
	blocks := md_parse("- top\n    - inner", context.temp_allocator)
	inner_level := -1
	for b in blocks {
		if b.kind == .List_Item && b.body == "inner" {
			inner_level = b.level
		}
	}
	testing.expect_value(t, inner_level, 4)
}

@(test)
test_md_parse_table :: proc(t: ^testing.T) {
	src := "| Name | Age |\n|:-----|----:|\n| al   | 3   |\n| bo   | 42  |\n\ntail"
	blocks := md_parse(src, context.temp_allocator)
	tbl := Md_Table{}
	found := false
	for b in blocks {
		if b.kind == .Table {
			found = true
			tbl = b.table
		}
	}
	testing.expect(t, found)
	testing.expect_value(t, len(tbl.header), 2)
	testing.expect_value(t, tbl.header[0], "Name")
	testing.expect_value(t, tbl.header[1], "Age")
	testing.expect_value(t, len(tbl.align), 2)
	testing.expect_value(t, tbl.align[0], u8('l'))
	testing.expect_value(t, tbl.align[1], u8('r'))
	testing.expect_value(t, len(tbl.rows), 2)
	testing.expect_value(t, tbl.rows[1][1], "42")
}

@(test)
test_md_parse_table_needs_sep :: proc(t: ^testing.T) {
	blocks := md_parse("| a | b |\nplain next", context.temp_allocator)
	for b in blocks {
		testing.expect(t, b.kind != .Table)
	}
}

@(test)
test_md_table_height_counts :: proc(t: ^testing.T) {
	blocks := md_parse("| a |\n|---|\n| 1 |\n| 2 |", context.temp_allocator)
	testing.expect_value(t, len(blocks), 1)
	testing.expect_value(t, blocks[0].kind, Md_Kind.Table)
	testing.expect_value(t, md_table_height(blocks[0].table, 40), 6)
}

@(test)
test_md_inline_flatten_bold_italic_strike :: proc(t: ^testing.T) {
	flat := md_inline_flatten("a **b** *c* ~~d~~ `e`", context.temp_allocator)
	testing.expect_value(t, flat.text, "a b c d e")
	testing.expect_value(t, flat.kinds[2], Md_Inline_Kind.Bold)
	testing.expect_value(t, flat.kinds[4], Md_Inline_Kind.Italic)
	testing.expect_value(t, flat.kinds[6], Md_Inline_Kind.Strike)
	testing.expect_value(t, flat.kinds[8], Md_Inline_Kind.Code)
	testing.expect_value(t, flat.kinds[0], Md_Inline_Kind.Normal)
}

@(test)
test_md_inline_flatten_underscore :: proc(t: ^testing.T) {
	flat := md_inline_flatten("__b__ _i_", context.temp_allocator)
	testing.expect_value(t, flat.text, "b i")
	testing.expect_value(t, flat.kinds[0], Md_Inline_Kind.Bold)
	testing.expect_value(t, flat.kinds[2], Md_Inline_Kind.Italic)
}

@(test)
test_md_inline_unmatched_stays_literal :: proc(t: ^testing.T) {
	flat := md_inline_flatten("a **open and `tick", context.temp_allocator)
	testing.expect_value(t, flat.text, "a **open and `tick")
}

@(test)
test_md_inline_ident_boundary :: proc(t: ^testing.T) {
	flat := md_inline_flatten("snake_case_name 2*3", context.temp_allocator)
	testing.expect_value(t, flat.text, "snake_case_name 2*3")
}

@(test)
test_md_inline_link :: proc(t: ^testing.T) {
	flat := md_inline_flatten("see [docs](https://x.io)", context.temp_allocator)
	testing.expect_value(t, flat.text, "see docs (https://x.io)")
	testing.expect_value(t, flat.kinds[4], Md_Inline_Kind.Link)
	testing.expect_value(t, flat.kinds[9], Md_Inline_Kind.Link_Url)
}

@(test)
test_md_inline_bare_url :: proc(t: ^testing.T) {
	flat := md_inline_flatten("open https://a.io/x) end", context.temp_allocator)
	testing.expect_value(t, flat.text, "open https://a.io/x) end")
	testing.expect_value(t, flat.kinds[6], Md_Inline_Kind.Link)
}

@(test)
test_md_text_line_count_markers :: proc(t: ^testing.T) {
	// Markers must not inflate the wrapped height.
	testing.expect_value(t, md_text_line_count("**abcd efgh**", 4), 3)
	testing.expect_value(t, md_text_line_count("plain", 4), 2)
}

@(test)
test_draw_inline_md_styles :: proc(t: ^testing.T) {
	buf := buffer_create(40, 4, context.temp_allocator)
	draw_inline_md_line(&buf, 0, 0, 40, "**b** *i* ~~s~~ `c`", {}, {}, {})
	b_cell := buffer_at(&buf, 0, 0)
	i_cell := buffer_at(&buf, 2, 0)
	s_cell := buffer_at(&buf, 4, 0)
	c_cell := buffer_at(&buf, 6, 0)
	testing.expect(t, b_cell != nil && .Bold in b_cell.style && b_cell.ch == 'b')
	testing.expect(t, i_cell != nil && .Italic in i_cell.style && i_cell.ch == 'i')
	testing.expect(t, s_cell != nil && .Strikethrough in s_cell.style && s_cell.ch == 's')
	testing.expect(t, c_cell != nil && c_cell.ch == 'c')
}

@(test)
test_draw_md_table_narrow :: proc(t: ^testing.T) {
	blocks := md_parse("| Name | Age |\n|------|-----|\n| al   | 3   |", context.temp_allocator)
	testing.expect_value(t, len(blocks), 1)
	buf := buffer_create(14, 8, context.temp_allocator)
	used := draw_md_table(&buf, 0, 0, 14, 8, 0, blocks[0].table, {}, {})
	testing.expect_value(t, used, 5)
	top := buffer_at(&buf, 0, 0)
	sep := buffer_at(&buf, 0, 2)
	testing.expect(t, top != nil && top.ch == '┌')
	testing.expect(t, sep != nil && sep.ch == '├')
}
