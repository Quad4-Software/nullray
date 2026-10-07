// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Markdown blocks in the transcript: headings, quotes, lists, tables,
code fences, rules and inline styled text.
*/

package app

import "core:fmt"
import "core:strings"
import "nullray:ui"

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
				body = "────────────────",
				prefix_fg = t.table_fg,
				body_fg = t.table_fg,
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
				body_fg = t.heading_fg,
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
			pfg := t.quote_fg
			style: ui.Style = {.Dim}
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
			marker := b.marker
			if len(marker) == 0 {
				marker = "•"
			}
			pad := strings.repeat(" ", min(b.level, 12), context.temp_allocator)
			pfx := fmt.tprintf("  %s%s ", pad, marker)
			pfg := t.accent_dim
			pstyle: ui.Style
			g := false
			body := b.body
			if first {
				pfx = label_prefix
				pfg = accent
				pstyle = {.Bold}
				g = gutter
				body = fmt.tprintf("%s %s", marker, body)
			}
			append(blocks, Transcript_Block{
				prefix = pfx,
				body = body,
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
		case .Table:
			pfx := ""
			g := false
			if first {
				pfx = label_prefix
				g = gutter
			}
			append(blocks, Transcript_Block{
				prefix = pfx,
				prefix_fg = accent,
				prefix_style = {.Bold},
				body_fg = fg,
				row_bg = row_bg,
				has_bg = has_bg,
				gutter = g,
				caret = caret && is_last,
				is_table = true,
				md_table = b.table,
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
				body_fg = t.code_fg,
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
