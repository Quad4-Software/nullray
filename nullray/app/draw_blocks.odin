// SPDX-License-Identifier: 0BSD
/*
Transcript block types and block assembly helpers.
*/

package app

import "core:fmt"
import "core:strings"
import "nullray:ui"

Transcript_Block :: struct {
	prefix:       string,
	body:         string,
	prefix_fg:    ui.Color,
	body_fg:      ui.Color,
	prefix_style: ui.Style,
	body_style:   ui.Style,
	row_bg:       ui.Color,
	has_bg:       bool,
	gutter:       bool,
	gap:          bool,
	caret:        bool,
	is_code:      bool,
	lang:         string,
	is_md:        bool,
	expand_kind:  string,
	expand_id:    string,
	expand_body:  string,
}

CODE_PREVIEW_LINES :: 16
CONTENT_X :: 2

@(private)
block_body_width :: proc(buf_width: int, prefix: string) -> int {
	return max(1, buf_width - CONTENT_X - ui.string_cols(prefix) - 1)
}

@(private)
block_height :: proc(block: Transcript_Block, buf_width: int) -> int {
	if block.gap {
		return 1
	}
	bw := block_body_width(buf_width, block.prefix)
	if block.is_code {
		lines := ui.wrap_line_count(block.body, max(1, buf_width - 5))
		if lines <= 0 {
			lines = 1
		}
		shown := min(lines, CODE_PREVIEW_LINES)
		// header + body + footer
		return 2 + shown
	}
	if len(block.body) == 0 {
		return 1
	}
	if block.is_md {
		return max(1, ui.md_text_line_count(block.body, bw))
	}
	return max(1, ui.wrap_line_count(block.body, bw))
}

@(private)
app_append_gap :: proc(blocks: ^[dynamic]Transcript_Block) {
	if len(blocks) == 0 {
		return
	}
	last := blocks[len(blocks) - 1]
	if last.gap {
		return
	}
	append(blocks, Transcript_Block{gap = true})
}

@(private)
app_append_md_content :: proc(
	blocks: ^[dynamic]Transcript_Block,
	label_prefix: string,
	content: string,
	accent: ui.Color,
	fg: ui.Color,
	caret: bool,
	row_bg: ui.Color = {},
	has_bg: bool = false,
	gutter: bool = false,
) {
	t := ui.theme()
	if len(content) == 0 {
		append(blocks, Transcript_Block{
			prefix = label_prefix,
			body = "",
			prefix_fg = accent,
			body_fg = fg,
			prefix_style = {.Bold},
			row_bg = row_bg,
			has_bg = has_bg,
			gutter = gutter,
			caret = caret,
			is_md = true,
		})
		return
	}
	md := ui.md_parse(content, context.temp_allocator)
	if len(md) == 0 {
		append(blocks, Transcript_Block{
			prefix = label_prefix,
			body = content,
			prefix_fg = accent,
			body_fg = fg,
			prefix_style = {.Bold},
			row_bg = row_bg,
			has_bg = has_bg,
			gutter = gutter,
			caret = caret,
			is_md = true,
		})
		return
	}
	first := true
	for b, idx in md {
		is_last := idx == len(md) - 1
		switch b.kind {
		case .Blank:
			continue
		case .Hr:
			append(blocks, Transcript_Block{
				prefix = "",
				body = "────────",
				prefix_fg = t.muted,
				body_fg = t.muted,
				body_style = {.Dim},
				row_bg = row_bg,
				has_bg = has_bg,
			})
		case .Heading:
			pfx := ""
			g := false
			if first {
				pfx = label_prefix
				g = gutter
			}
			append(blocks, Transcript_Block{
				prefix = pfx,
				body = b.body,
				prefix_fg = accent,
				body_fg = t.title,
				prefix_style = {.Bold},
				body_style = {.Bold},
				row_bg = row_bg,
				has_bg = has_bg,
				gutter = g,
				caret = caret && is_last,
				is_md = true,
			})
			first = false
		case .Quote:
			pfx := "│ "
			style: ui.Style = {.Dim}
			pfg := t.muted
			g := false
			if first {
				pfx = label_prefix
				pfg = accent
				style = {.Bold}
				g = gutter
			}
			append(blocks, Transcript_Block{
				prefix = pfx,
				body = b.body,
				prefix_fg = pfg,
				body_fg = t.muted,
				prefix_style = style,
				body_style = {.Dim},
				row_bg = row_bg,
				has_bg = has_bg,
				gutter = g,
				caret = caret && is_last,
				is_md = true,
			})
			first = false
		case .List_Item:
			pfx := "  • "
			pfg := t.muted
			pstyle: ui.Style
			g := false
			if first {
				pfx = label_prefix
				pfg = accent
				pstyle = {.Bold}
				g = gutter
			}
			append(blocks, Transcript_Block{
				prefix = pfx,
				body = b.body,
				prefix_fg = pfg,
				body_fg = fg,
				prefix_style = pstyle,
				row_bg = row_bg,
				has_bg = has_bg,
				gutter = g,
				caret = caret && is_last,
				is_md = true,
			})
			first = false
		case .Code:
			lang := b.lang
			if len(lang) == 0 {
				lang = "code"
			}
			append(blocks, Transcript_Block{
				prefix = "",
				body = b.body,
				prefix_fg = t.muted,
				body_fg = t.assistant_fg,
				is_code = true,
				lang = lang,
				caret = caret && is_last,
				expand_kind = "code",
				expand_body = b.body,
			})
			first = false
		case .Text:
			pfx := ""
			pstyle: ui.Style
			g := false
			if first {
				pfx = label_prefix
				pstyle = {.Bold}
				g = gutter
			}
			append(blocks, Transcript_Block{
				prefix = pfx,
				body = b.body,
				prefix_fg = accent,
				body_fg = fg,
				prefix_style = pstyle,
				row_bg = row_bg,
				has_bg = has_bg,
				gutter = g,
				caret = caret && is_last,
				is_md = true,
			})
			first = false
		}
	}
}

@(private)
tool_artifact_stub :: proc(content: string, allocator := context.allocator) -> (string, bool) {
	idx := strings.index(content, "artifact=")
	if idx < 0 {
		return "", false
	}
	rest := content[idx + len("artifact="):]
	end := 0
	for end < len(rest) {
		c := rest[end]
		if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-' || c == '_' {
			end += 1
			continue
		}
		break
	}
	if end == 0 {
		return "", false
	}
	id := rest[:end]
	head := content
	nl := strings.index_byte(content, '\n')
	if nl > 0 {
		head = content[:nl]
	}
	if len(head) > 120 {
		head = ui.truncate_utf8_bytes(head, 120)
	}
	return fmt.aprintf("%s (expand: /artifact %s)", head, id, allocator = allocator), true
}
