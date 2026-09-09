// SPDX-License-Identifier: 0BSD
/*
In-app transcript text selection and clipboard copy.
*/

package app

import "core:fmt"
import "core:strings"
import "core:unicode/utf8"
import "nullray:sandbox"
import "nullray:ui"

app_sel_clear_rows :: proc(a: ^App) {
	for s in a.sel_rows {
		delete(s)
	}
	clear(&a.sel_rows)
	a.sel_rows_top = 0
}

app_sel_clear :: proc(a: ^App) {
	a.sel_dragging = false
	a.sel_has = false
	a.sel_ax = 0
	a.sel_ay = 0
	a.sel_bx = 0
	a.sel_by = 0
}

app_sel_destroy :: proc(a: ^App) {
	app_sel_clear_rows(a)
	app_sel_clear(a)
}

app_sel_begin_frame :: proc(a: ^App, rows_top: int) {
	app_sel_clear_rows(a)
	a.sel_rows_top = rows_top
}

app_sel_push_row :: proc(a: ^App, text: string) {
	append(&a.sel_rows, strings.clone(text))
}

app_sel_capture_buffer :: proc(a: ^App, buf: ^ui.Buffer, y0, y1, x0, x1: int) {
	app_sel_begin_frame(a, y0)
	x_start := max(0, x0)
	x_end := min(buf.width - 1, x1)
	for y in y0 ..= y1 {
		if y < 0 || y >= buf.height {
			app_sel_push_row(a, "")
			continue
		}
		b: strings.Builder
		strings.builder_init(&b, context.temp_allocator)
		for x in x_start ..= x_end {
			cell := ui.buffer_at(buf, x, y)
			if cell == nil || cell.ch == ui.CELL_WIDE_CONT {
				continue
			}
			ch := cell.ch
			if ch == 0 {
				ch = ' '
			}
			strings.write_rune(&b, ch)
		}
		app_sel_push_row(a, strings.trim_right_space(strings.to_string(b)))
	}
}

@(private)
app_sel_norm :: proc(a: ^App) -> (x0, y0, x1, y1: int) {
	x0, y0 = a.sel_ax, a.sel_ay
	x1, y1 = a.sel_bx, a.sel_by
	if y1 < y0 || (y1 == y0 && x1 < x0) {
		x0, y0, x1, y1 = x1, y1, x0, y0
	}
	return
}

app_sel_contains :: proc(a: ^App, x, y: int) -> bool {
	if !a.sel_has && !a.sel_dragging {
		return false
	}
	x0, y0, x1, y1 := app_sel_norm(a)
	if y < y0 || y > y1 {
		return false
	}
	if y0 == y1 {
		return x >= min(x0, x1) && x <= max(x0, x1)
	}
	if y == y0 {
		return x >= x0
	}
	if y == y1 {
		return x <= x1
	}
	return true
}

@(private)
app_sel_row_index :: proc(a: ^App, screen_y: int) -> int {
	return screen_y - a.sel_rows_top
}

app_sel_extract :: proc(a: ^App, allocator := context.temp_allocator) -> string {
	if !a.sel_has && !a.sel_dragging {
		return ""
	}
	x0, y0, x1, y1 := app_sel_norm(a)
	b: strings.Builder
	strings.builder_init(&b, allocator)
	first := true
	for sy in y0 ..= y1 {
		ri := app_sel_row_index(a, sy)
		if ri < 0 || ri >= len(a.sel_rows) {
			continue
		}
		line := a.sel_rows[ri]
		start_col := 0
		end_col := ui.string_cols(line)
		if sy == y0 {
			start_col = x0
		}
		if sy == y1 {
			end_col = x1 + 1
		}
		chunk := app_sel_slice_cols(line, start_col, end_col, context.temp_allocator)
		if !first {
			strings.write_rune(&b, '\n')
		}
		first = false
		strings.write_string(&b, chunk)
	}
	return strings.to_string(b)
}

@(private)
app_sel_slice_cols :: proc(line: string, start_col, end_col: int, allocator := context.temp_allocator) -> string {
	if end_col <= start_col || len(line) == 0 {
		return ""
	}
	col := 0
	byte_start := 0
	byte_end := len(line)
	found_start := false
	i := 0
	for i < len(line) {
		r, sz := utf8.decode_rune_in_string(line[i:])
		if sz <= 0 {
			break
		}
		w := max(1, ui.rune_cols(r))
		if !found_start && col + w > start_col {
			byte_start = i
			found_start = true
		}
		if col >= end_col {
			byte_end = i
			break
		}
		col += w
		i += sz
		if found_start && col >= end_col {
			byte_end = i
			break
		}
	}
	if !found_start {
		return ""
	}
	if byte_end < byte_start {
		byte_end = byte_start
	}
	return strings.clone(line[byte_start:byte_end], allocator)
}

app_sel_copy :: proc(a: ^App) -> bool {
	text := app_sel_extract(a, context.temp_allocator)
	text = strings.trim_right_space(text)
	if len(text) == 0 {
		app_toast(a, "nothing selected", .Warn)
		return false
	}
	safe := sandbox.redact_secrets(text, context.temp_allocator)
	if ui.clipboard_copy(safe) {
		app_toast_ok(a, "copied to clipboard")
		return true
	}
	app_toast_error(a, "clipboard copy failed")
	return false
}

app_sel_start :: proc(a: ^App, x, y: int) {
	a.sel_dragging = true
	a.sel_has = true
	a.sel_ax = x
	a.sel_ay = y
	a.sel_bx = x
	a.sel_by = y
	app_mark_dirty(a)
}

app_sel_update :: proc(a: ^App, x, y: int) {
	if !a.sel_dragging {
		return
	}
	a.sel_bx = x
	a.sel_by = y
	app_mark_dirty(a)
}

app_sel_finish :: proc(a: ^App, x, y: int, copy := true) {
	if !a.sel_dragging {
		return
	}
	a.sel_bx = x
	a.sel_by = y
	a.sel_dragging = false
	a.sel_has = true
	if copy {
		_ = app_sel_copy(a)
	}
	app_mark_dirty(a)
}

app_sel_click_message :: proc(a: ^App, screen_y: int) -> bool {
	ri := app_sel_row_index(a, screen_y)
	if ri < 0 || ri >= len(a.sel_rows) {
		return false
	}
	// Expand to contiguous non-empty rows around click for a soft "select message" feel.
	lo := ri
	hi := ri
	for lo > 0 && len(strings.trim_space(a.sel_rows[lo - 1])) > 0 {
		lo -= 1
	}
	for hi + 1 < len(a.sel_rows) && len(strings.trim_space(a.sel_rows[hi + 1])) > 0 {
		hi += 1
	}
	a.sel_dragging = false
	a.sel_has = true
	a.sel_ax = 0
	a.sel_ay = a.sel_rows_top + lo
	a.sel_bx = max(0, ui.string_cols(a.sel_rows[hi]) - 1)
	a.sel_by = a.sel_rows_top + hi
	app_mark_dirty(a)
	return true
}

app_apply_selection_style :: proc(buf: ^ui.Buffer, a: ^App) {
	if !a.sel_has && !a.sel_dragging {
		return
	}
	x0, y0, x1, y1 := app_sel_norm(a)
	for y in y0 ..= y1 {
		if y < 0 || y >= buf.height {
			continue
		}
		for x in 0 ..< buf.width {
			if !app_sel_contains(a, x, y) {
				continue
			}
			cell := ui.buffer_at(buf, x, y)
			if cell != nil {
				cell.style += {.Reverse}
			}
		}
	}
}
