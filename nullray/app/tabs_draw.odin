// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Tab strip rendering: label sizing, overflow scroll window, hit boxes.
*/

package app

import "core:fmt"
import "core:strings"
import "nullray:ui"

@(private)
tab_label :: proc(name: string) -> string {
	if len(name) == 0 {
		return "default"
	}
	if ui.string_cols(name) > TAB_LABEL_MAX {
		return fmt.tprintf("%.*s…", TAB_LABEL_MAX - 1, name)
	}
	return name
}

// Display width of one strip cell: indicator + space + label + space + separator.
@(private)
tab_cell_w :: proc(name: string) -> int {
	return min(ui.string_cols(name), TAB_LABEL_MAX) + 4
}

// Horizontal strip at row y: busy tabs spin, finished-away tabs flag done,
// a trailing + opens a new tab, and ‹/› mark scroll overflow. The window
// scrolls to keep the active tab visible.
app_draw_tabs :: proc(buf: ^ui.Buffer, a: ^App, y: int) {
	t := ui.theme()
	clear(&a.tab_hits)
	a.tab_plus_x = -1
	n := len(a.tabs)
	if n == 0 {
		return
	}
	if a.tab_scroll > a.active_tab {
		a.tab_scroll = a.active_tab
	}
	if a.tab_scroll >= n {
		a.tab_scroll = n - 1
	}
	scroll := max(a.tab_scroll, 0)

	PLUS_W :: 4 // " +" plus separator room
	EDGE_W :: 2 // "‹ " or " ›"
	avail := max(buf.width - 1 - PLUS_W, 4)

	// Advance the window until the active tab is visible.
	for scroll < a.active_tab {
		lmark := scroll > 0 ? EDGE_W : 0
		x := lmark
		i := scroll
		for i < n {
			rmark := i < n - 1 ? EDGE_W : 0
			w := tab_cell_w(a.tabs[i].sess.name)
			if x + w + rmark > avail {
				break
			}
			x += w
			i += 1
		}
		if a.active_tab < i {
			break
		}
		scroll += 1
	}
	a.tab_scroll = scroll

	x := 0
	ui.buffer_text(buf, x, y, " ", t.muted, t.status_bg)
	x += 1
	if scroll > 0 {
		ui.buffer_text(buf, x, y, "‹", t.muted, t.status_bg)
		x += EDGE_W
	}
	for i := scroll; i < n; i += 1 {
		tab := a.tabs[i]
		label := tab_label(tab.sess.name)
		indicator := " "
		if tab.sess.busy {
			indicator = ui.spinner_frame(&a.spinner)
		} else if tab.done_pending {
			indicator = "●"
		}
		w := ui.string_cols(label) + 4
		rmark := i < n - 1 ? EDGE_W : 0
		if x + w + rmark > buf.width - PLUS_W {
			ui.buffer_text(buf, x, y, "›", t.muted, t.status_bg)
			x += EDGE_W
			break
		}
		fg := t.muted
		bg := t.status_bg
		style: ui.Style
		if i == a.active_tab {
			fg = t.accent
			style = {.Bold}
		} else if tab.sess.busy || tab.done_pending {
			fg = t.accent
		}
		text := fmt.tprintf("%s %s ", indicator, label)
		append(&a.tab_hits, Tab_Hit{i = i, x0 = x, x1 = x + w})
		ui.buffer_text(buf, x, y, text, fg, bg, style)
		x += ui.string_cols(text)
		ui.buffer_text(buf, x, y, "│", t.border, t.status_bg)
		x += 1
	}
	plus_fg := t.accent
	if n >= TAB_MAX {
		plus_fg = t.muted
	}
	a.tab_plus_x = x
	ui.buffer_text(buf, x, y, " +", plus_fg, t.status_bg, {.Bold})
	x += 2
	for x < buf.width {
		ui.buffer_put(buf, x, y, ' ', t.fg, t.status_bg, {})
		x += 1
	}
}
