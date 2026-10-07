// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Pipe table parsing and boxed rendering.

A table needs a header row containing '|' directly followed by a
separator row of dash cells like |---|---|. Separator cells may carry
':' for left/center/right alignment. Rows keep subslices of the source.
*/

package ui

import "base:runtime"
import "core:strings"

MD_TABLE_MAX_COLS :: 12
MD_TABLE_MAX_ROWS :: 200

Md_Table :: struct {
	header: []string,
	rows:   [][]string,
	align:  []u8, // 'l', 'r' or 'c' per column
}

md_table_height :: proc(tbl: Md_Table, width: int) -> int {
	if width <= 0 || len(tbl.header) == 0 {
		return 0
	}
	// top border + header + separator + rows + bottom border
	return len(tbl.rows) + 4
}

// Parse a table starting at line_start, where line_end ends the header
// line. Returns the table and the byte index of the next unconsumed
// line.
@(private)
md_table_at :: proc(
	src: string,
	line_start, line_end: int,
	allocator: runtime.Allocator,
) -> (tbl: Md_Table, next_i: int, ok: bool) {
	line := src[line_start:line_end]
	if !md_table_rowish(line) {
		return {}, line_start, false
	}
	ns := line_end + 1
	if ns > len(src) {
		return {}, line_start, false
	}
	ne := ns
	for ne < len(src) && src[ne] != '\n' {
		ne += 1
	}
	align, sep_ok := md_table_sep(src[ns:ne], allocator)
	if !sep_ok {
		return {}, line_start, false
	}
	header := md_table_cells(line, allocator)
	if len(header) == 0 {
		return {}, line_start, false
	}
	tbl.header = header
	tbl.align = align

	rows: [dynamic][]string
	rows.allocator = allocator
	i := ne
	if i < len(src) {
		i += 1
	}
	for i < len(src) && len(rows) < MD_TABLE_MAX_ROWS {
		le := i
		for le < len(src) && src[le] != '\n' {
			le += 1
		}
		l := src[i:le]
		if !md_table_rowish(l) {
			break
		}
		// A second separator-looking row mid-table is dropped.
		if _, is_sep := md_table_sep(l, context.temp_allocator); !is_sep {
			append(&rows, md_table_cells(l, allocator))
		}
		i = le
		if i < len(src) {
			i += 1
		}
	}
	tbl.rows = rows[:]
	return tbl, i, true
}

@(private)
md_table_rowish :: proc(line: string) -> bool {
	trimmed := strings.trim_space(line)
	if len(trimmed) == 0 || strings.has_prefix(trimmed, "```") {
		return false
	}
	return strings.contains(trimmed, "|")
}

// A separator row: | cells of dashes with optional ':' alignment.
@(private)
md_table_sep :: proc(line: string, allocator: runtime.Allocator) -> (align: []u8, ok: bool) {
	trimmed := strings.trim_space(line)
	if !strings.contains(trimmed, "|") {
		return nil, false
	}
	cells := md_table_cells(trimmed, allocator)
	if len(cells) == 0 {
		return nil, false
	}
	out := make([]u8, len(cells), allocator)
	for c, idx in cells {
		a, valid := md_sep_cell_align(c)
		if !valid {
			return nil, false
		}
		out[idx] = a
	}
	return out, true
}

@(private)
md_sep_cell_align :: proc(cell: string) -> (u8, bool) {
	c := strings.trim_space(cell)
	left := strings.has_prefix(c, ":")
	right := strings.has_suffix(c, ":")
	c = strings.trim(c, ":")
	if len(c) == 0 {
		return 'l', false
	}
	for i in 0 ..< len(c) {
		if c[i] != '-' {
			return 'l', false
		}
	}
	if left && right {
		return 'c', true
	}
	if right {
		return 'r', true
	}
	return 'l', true
}

@(private)
md_table_cells :: proc(line: string, allocator: runtime.Allocator) -> []string {
	t := strings.trim_space(line)
	t = strings.trim_prefix(t, "|")
	t = strings.trim_suffix(t, "|")
	parts := strings.split(t, "|", allocator)
	out: [dynamic]string
	out.allocator = allocator
	for p in parts {
		if len(out) >= MD_TABLE_MAX_COLS {
			break
		}
		append(&out, strings.trim_space(p))
	}
	return out[:]
}

@(private)
md_table_widths :: proc(tbl: Md_Table, ncols: int, allocator: runtime.Allocator) -> []int {
	widths := make([]int, ncols, allocator)
	for c in 0 ..< ncols {
		w := 1
		if c < len(tbl.header) {
			w = max(w, string_cols(md_inline_plain(tbl.header[c], context.temp_allocator)))
		}
		for row in tbl.rows {
			if c < len(row) {
				cw := string_cols(md_inline_plain(row[c], context.temp_allocator))
				w = max(w, cw)
			}
		}
		widths[c] = w
	}
	return widths
}

@(private)
md_tput :: proc(b: ^Buffer, x, y, x_end: int, ch: rune, fg, bg: Color, style: Style = {}) {
	if x < x_end {
		buffer_put(b, x, y, ch, fg, bg, style)
	}
}

// Border line: left edge, column dashes, junctions, right edge.
@(private)
md_table_border :: proc(
	b: ^Buffer,
	x, y, x_end: int,
	widths: []int,
	left, mid, right: rune,
	fg, bg: Color,
) {
	cx := x
	md_tput(b, cx, y, x_end, left, fg, bg)
	cx += 1
	for w, c in widths {
		for _ in 0 ..< w + 2 {
			md_tput(b, cx, y, x_end, '─', fg, bg)
			cx += 1
		}
		ch := mid
		if c == len(widths) - 1 {
			ch = right
		}
		md_tput(b, cx, y, x_end, ch, fg, bg)
		cx += 1
	}
}

// One cell row between vertical bars. Cells clip at their column width
// and keep inline code/bold styling.
@(private)
md_table_row :: proc(
	b: ^Buffer,
	x, y, x_end: int,
	cells: []string,
	widths: []int,
	align: []u8,
	header: bool,
	fg, code_fg, bg: Color,
) {
	t := theme()
	base_fg := fg
	base_style: Style
	if header {
		base_fg = t.heading_fg
		base_style = {.Bold}
	}
	cx := x
	md_tput(b, cx, y, x_end, '│', t.table_fg, bg)
	cx += 1
	for w, c in widths {
		md_tput(b, cx, y, x_end, ' ', base_fg, bg)
		cx += 1
		text_start := cx
		pw := 0
		flat: Md_Flat
		if c < len(cells) {
			flat = md_inline_flatten(cells[c], context.temp_allocator)
			pw = string_cols(flat.text)
		}
		pad := 0
		if pw < w {
			pad = w - pw
		}
		a := u8('l')
		if c < len(align) {
			a = align[c]
		}
		pad_left := 0
		if a == 'r' {
			pad_left = pad
		} else if a == 'c' {
			pad_left = pad / 2
		}
		for _ in 0 ..< pad_left {
			md_tput(b, cx, y, x_end, ' ', base_fg, bg)
			cx += 1
		}
		if c < len(cells) {
			cx += draw_flat_md_line(
				b,
				cx,
				y,
				min(w - pad_left, x_end - cx),
				flat.text,
				flat.kinds,
				base_fg,
				code_fg,
				bg,
				base_style,
			)
		}
		for cx < text_start + w {
			md_tput(b, cx, y, x_end, ' ', base_fg, bg)
			cx += 1
		}
		md_tput(b, cx, y, x_end, ' ', base_fg, bg)
		cx += 1
		md_tput(b, cx, y, x_end, '│', t.table_fg, bg)
		cx += 1
	}
}

draw_md_table :: proc(
	b: ^Buffer,
	x, y, width, max_lines, skip: int,
	tbl: Md_Table,
	fg, bg: Color,
) -> int {
	if width <= 0 || max_lines <= 0 || len(tbl.header) == 0 {
		return 0
	}
	t := theme()
	ncols := len(tbl.header)
	widths := md_table_widths(tbl, ncols, context.temp_allocator)
	overhead := ncols * 3 + 1
	for md_widths_total(widths) + overhead > width {
		c, w := md_widths_max(widths)
		if w <= 1 {
			break
		}
		widths[c] = w - 1
	}
	x_end := x + width
	drawn := 0
	vis := 0

	if vis >= skip && drawn < max_lines {
		md_table_border(b, x, y + drawn, x_end, widths, '┌', '┬', '┐', t.table_fg, bg)
		drawn += 1
	}
	vis += 1
	if vis >= skip && drawn < max_lines {
		md_table_row(b, x, y + drawn, x_end, tbl.header, widths, tbl.align, true, fg, t.code_fg, bg)
		drawn += 1
	}
	vis += 1
	if vis >= skip && drawn < max_lines {
		md_table_border(b, x, y + drawn, x_end, widths, '├', '┼', '┤', t.table_fg, bg)
		drawn += 1
	}
	vis += 1
	for row in tbl.rows {
		if vis >= skip && drawn < max_lines {
			md_table_row(b, x, y + drawn, x_end, row, widths, tbl.align, false, fg, t.code_fg, bg)
			drawn += 1
		}
		vis += 1
	}
	if vis >= skip && drawn < max_lines {
		md_table_border(b, x, y + drawn, x_end, widths, '└', '┴', '┘', t.table_fg, bg)
		drawn += 1
	}
	vis += 1
	return drawn
}

@(private)
md_widths_total :: proc(widths: []int) -> int {
	n := 0
	for w in widths {
		n += w
	}
	return n
}

@(private)
md_widths_max :: proc(widths: []int) -> (col, w: int) {
	for v, i in widths {
		if v > w {
			w = v
			col = i
		}
	}
	return col, w
}
