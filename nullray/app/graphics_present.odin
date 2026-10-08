// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Post-present Kitty graphics paint. Called after the ANSI cell buffer is
flushed so image payloads land on top of reserved pane cells.
*/

package app

import "core:fmt"
import "core:os"
import "nullray:ui"

app_after_present :: proc(user: rawptr) {
	a := cast(^App)user
	if a == nil || a.loop == nil {
		return
	}
	if !a.view_open || !a.view_is_image || a.view_err || len(a.view_path) == 0 {
		return
	}
	if !ui.kitty_graphics_enabled() {
		return
	}
	cols := a.view_image_cols
	rows := a.view_image_rows
	if cols <= 0 || rows <= 0 {
		return
	}
	// Move cursor to the pane image origin (1-based ANSI). Layout: title/tabs
	// then pane_y from view layout; image body starts one row under the header
	// strip when recent files exist, else under the title-like header.
	lay := app_view_layout(a, a.loop.term.width, a.loop.term.height)
	if !lay.open {
		return
	}
	// Approximate origin: pane_x+1, body top after strip+header.
	y := lay.pane_y + 1 // header
	if len(a.view_recent) > 0 {
		y += 1
	}
	x := lay.pane_x + 1
	if x < 0 {
		x = 0
	}
	if y < 0 {
		y = 0
	}
	// Cursor position sequence then draw.
	seq := fmt.tprintf("\x1b[%d;%dH", y + 1, x + 1)
	_, _ = os.write(os.stdout, transmute([]u8)seq)
	id := a.view_kitty_id
	if id == 0 {
		id = ui.kitty_next_id()
		a.view_kitty_id = id
	}
	_ = ui.kitty_draw_image_file(a.view_path, cols, rows, id)
}
