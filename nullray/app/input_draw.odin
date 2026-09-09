// SPDX-License-Identifier: 0BSD
/*
Multiline input box painter and click-expand hit testing.
*/

package app

import "core:fmt"
import "core:strings"
import "core:unicode/utf8"
import "nullray:constants"
import "nullray:store"
import "nullray:ui"

Expand_Hit :: struct {
	y0, y1: int,
	kind:   string,
	id:     string,
	body:   string,
}

app_input_rows :: proc(a: ^App, width: int) -> int {
	text := strings.to_string(a.input)
	inner := max(1, width - 3 - ui.string_cols("❯ "))
	n := ui.wrap_line_count(text, inner)
	if n < 1 {
		n = 1
	}
	return min(n, constants.INPUT_MAX_ROWS)
}

app_draw_input_box :: proc(buf: ^ui.Buffer, a: ^App, y0, height: int, fg, bg, prompt_fg: ui.Color) {
	prompt := "❯ "
	text := strings.to_string(a.input)
	a.cursor = ui.cursor_snap_boundary(text, a.cursor)
	inner_w := max(1, buf.width - 3 - ui.string_cols(prompt))
	line, col := wrap_pos(text, a.cursor, inner_w)
	total := ui.wrap_line_count(text, inner_w)
	skip := max(0, total - height)
	if line < skip {
		skip = line
	}
	if line >= skip + height {
		skip = max(0, line - height + 1)
	}

	for row in 0 ..< height {
		y := y0 + row
		ui.buffer_fill_rect(buf, 0, y, buf.width, 1, ' ', fg, bg)
		if row == 0 {
			ui.buffer_text(buf, 1, y, prompt, prompt_fg, bg, {.Bold})
		}
		px := 1 + ui.string_cols(prompt)
		_ = ui.draw_wrapped_text_skip(buf, px, y, inner_w, 1, text, skip + row, fg, bg)
		if line == skip + row {
			cx := px + col
			if cx >= 1 && cx < buf.width {
				cell := ui.buffer_at(buf, cx, y)
				if cell != nil {
					cell.style += {.Reverse}
				}
			}
		}
	}
}

@(private)
wrap_pos :: proc(text: string, cursor, width: int) -> (line, col: int) {
	if width <= 0 {
		return 0, 0
	}
	c := ui.cursor_snap_boundary(text, cursor)
	line = 0
	col = 0
	i := 0
	for i < c {
		r, size := utf8.decode_rune_in_string(text[i:])
		if size <= 0 {
			break
		}
		if r == '\n' {
			line += 1
			col = 0
			i += size
			continue
		}
		w := max(1, ui.rune_cols(r))
		if col + w > width {
			line += 1
			col = 0
		}
		col += w
		i += size
	}
	return line, col
}

app_expand_hits_clear :: proc(a: ^App) {
	for h in a.expand_hits {
		delete(h.kind)
		delete(h.id)
		delete(h.body)
	}
	clear(&a.expand_hits)
}

@(private)
app_expand_hit_push :: proc(a: ^App, y0, y1: int, kind, id, body: string) {
	append(
		&a.expand_hits,
		Expand_Hit{
			y0 = y0,
			y1 = y1,
			kind = strings.clone(kind),
			id = strings.clone(id),
			body = strings.clone(body),
		},
	)
}

@(private)
app_try_click_expand :: proc(a: ^App, mx, my: int) -> bool {
	_ = mx
	if a.loop == nil {
		return false
	}
	if !app_mouse_in_transcript(a, mx, my) {
		return false
	}
	for row in a.expand_hits {
		if my >= row.y0 && my <= row.y1 {
			if row.kind == "artifact" && len(row.id) > 0 {
				body, err := store.artifact_read(row.id, context.temp_allocator)
				if len(err) > 0 {
					app_toast_warn(a, err)
					return true
				}
				_ = app_view_open_text(a, fmt.tprintf("artifact %s", row.id), body)
				return true
			}
			if row.kind == "code" && len(row.body) > 0 {
				_ = app_view_open_text(a, "code", row.body)
				return true
			}
		}
	}
	return false
}
