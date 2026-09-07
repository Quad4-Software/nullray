// SPDX-License-Identifier: 0BSD
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
