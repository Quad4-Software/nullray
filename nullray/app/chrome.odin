// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Responsive chrome geometry for the main TUI.

Computes title/tab/transcript/status/input row ranges from terminal size so
narrow, tall, wide, and short layouts keep a usable message area.
*/

package app

import "core:fmt"
import "core:strings"
import "nullray:constants"
import "nullray:subagent"
import "nullray:ui"

// Compact thresholds. Below these, chrome drops nonessential rows/labels.
CHROME_NARROW_W :: 48
CHROME_TIGHT_W :: 28
CHROME_SHORT_H :: 14
CHROME_TINY_H :: 9

Chrome :: struct {
	width:         int,
	height:        int,
	title_y:       int,
	tabs_y:        int, // -1 when the tab strip is hidden
	agents_y:      int, // -1 when the subagent activity strip is hidden
	plan_y:        int, // -1 when the tool/plan strip is hidden
	sep_y:         int,
	msg_top:       int,
	msg_bottom:    int,
	status_y:      int,
	input_y:       int,
	input_rows:    int,
	show_tabs:     bool,
	show_agents:   bool,
	show_plan:     bool,
	show_sep:      bool,
	narrow:        bool,
	tight:         bool,
	short:         bool,
	agents_living: int, // running+blocked children (for draw/tick)
}

// How many input rows fit without crushing the transcript.
app_input_rows_capped :: proc(a: ^App, width, height: int) -> int {
	want := app_input_rows(a, width)
	// Reserve: title + optional tab/sep + status + at least 1 transcript row.
	reserve := 3 // title + status + 1 msg
	if height >= CHROME_SHORT_H {
		reserve += 2 // tab strip + separator on roomy heights
	}
	room := max(1, height - reserve)
	cap := min(want, room)
	if height < CHROME_TINY_H {
		cap = min(cap, 1)
	} else if height < CHROME_SHORT_H {
		cap = min(cap, 2)
	}
	return max(1, cap)
}

app_chrome :: proc(a: ^App, width, height: int) -> Chrome {
	c: Chrome
	c.width = max(1, width)
	c.height = max(1, height)
	c.narrow = c.width < CHROME_NARROW_W
	c.tight = c.width < CHROME_TIGHT_W
	c.short = c.height < CHROME_SHORT_H

	c.input_rows = app_input_rows_capped(a, c.width, c.height)
	c.input_y = max(0, c.height - c.input_rows)
	// Title always owns row 0 when height allows. Status sits above input
	// and below title so they never paint the same cell.
	c.title_y = 0
	c.agents_y = -1
	c.show_agents = false
	c.agents_living = 0
	if c.height <= 1 {
		// Degenerate: everything collapses onto row 0.
		c.status_y = 0
		c.input_y = 0
		c.input_rows = 1
		c.msg_top = 0
		c.msg_bottom = 0
		c.tabs_y = -1
		c.sep_y = -1
		c.show_tabs = false
		c.show_sep = false
		return c
	}
	if c.height == 2 {
		// Title + input only; drop status and tabs.
		c.status_y = 0
		c.input_y = 1
		c.input_rows = 1
		c.msg_top = 0
		c.msg_bottom = 0
		c.tabs_y = -1
		c.sep_y = -1
		c.show_tabs = false
		c.show_sep = false
		return c
	}
	// Status always sits strictly above the input block.
	c.status_y = max(1, c.input_y - 1)
	if c.status_y >= c.input_y {
		c.status_y = max(1, c.input_y - 1)
	}
	// Leave at least one row free above status for title-adjacent chrome.
	// If multi-line input eats the whole window, shrink it so title+status+msg fit.
	if c.input_y <= 2 && c.height > 3 {
		c.input_rows = max(1, c.height - 3)
		c.input_y = c.height - c.input_rows
		c.status_y = max(1, c.input_y - 1)
	}

	c.agents_living = subagent.roster_living_children(&a.subagents.roster)

	// Hide tabs on very short terminals or when there is nothing to show.
	// Need room for title, tab, optional agents/plan/sep, msg, status, input.
	c.show_tabs = !c.short && len(a.tabs) > 0 && c.height >= 8 && c.status_y >= 3
	// Agent strip when children are living and the window is not tiny.
	c.show_agents = c.agents_living > 0 && !c.tight && c.height >= 10 && c.status_y >= 4
	// Plan/tool strip: busy with a live tool, or seeded plan steps.
	c.show_plan = !c.tight && c.height >= 10 && c.status_y >= 4 &&
		((a.session != nil && a.session.busy && len(a.session.live_tool) > 0) ||
			(a.session != nil && len(a.session.plan_steps) > 0))
	c.show_sep = !c.short && c.height >= 8 && c.status_y >= 4

	y := 1
	if c.show_tabs && y < c.status_y {
		c.tabs_y = y
		y += 1
	} else {
		c.tabs_y = -1
		c.show_tabs = false
	}
	if c.show_agents && y < c.status_y {
		c.agents_y = y
		y += 1
	} else {
		c.agents_y = -1
		c.show_agents = false
	}
	if c.show_plan && y < c.status_y {
		c.plan_y = y
		y += 1
	} else {
		c.plan_y = -1
		c.show_plan = false
	}
	if c.show_sep && y < c.status_y {
		c.sep_y = y
		y += 1
	} else {
		c.sep_y = -1
		c.show_sep = false
	}
	// Transcript sits between chrome top and the status rule. Cap so it
	// never claims the status or input rows.
	c.msg_top = min(y, c.status_y)
	if c.msg_top < 1 {
		c.msg_top = 1
	}
	if c.msg_top > c.status_y {
		c.msg_top = c.status_y
	}
	rule_y := c.status_y - 1
	if rule_y > c.msg_top {
		c.msg_bottom = rule_y - 1
	} else if c.status_y > c.msg_top {
		c.msg_bottom = c.status_y - 1
	} else {
		c.msg_bottom = c.msg_top
	}
	if c.msg_bottom < c.msg_top {
		c.msg_bottom = c.msg_top
	}
	if c.msg_bottom >= c.status_y && c.status_y > c.msg_top {
		c.msg_bottom = c.status_y - 1
	}
	// Guarantee status never collides with title when there is room.
	if c.status_y == c.title_y && c.height > 2 {
		c.status_y = 1
		if c.status_y >= c.input_y {
			c.status_y = max(1, c.input_y - 1)
		}
	}
	return c
}

app_chrome_msg_h :: proc(c: Chrome) -> int {
	return max(1, c.msg_bottom - c.msg_top + 1)
}

// Overlay body height (help/status/history) between title chrome and footer.
app_chrome_overlay_h :: proc(c: Chrome) -> int {
	return max(1, c.status_y - c.msg_top)
}

// Compact help text for the bottom status bar.
app_chrome_help_right :: proc(a: ^App, c: Chrome) -> string {
	if a.view_open {
		if c.narrow {
			return "Tab · Esc"
		}
		return "Tab focus · Left/Right files · Esc close"
	}
	if a.sel_has || a.sel_dragging {
		if c.narrow {
			return "/copy · Esc"
		}
		return "drag select · copies · Ctrl-C · Esc clear"
	}
	if c.tight {
		return "/ · ?"
	}
	if c.narrow {
		return "/ · ? · ^q"
	}
	return "type / · ? help · ^q quit"
}

// Brand label: full name, short mark on tight widths.
app_chrome_brand :: proc(c: Chrome) -> string {
	if c.tight {
		return "nr"
	}
	return constants.APP_NAME
}

// Version label on the title bar right side. Appends short commit when width
// allows and the build baked one in.
app_chrome_ver_label :: proc(c: Chrome) -> string {
	if c.tight {
		return "?"
	}
	commit := constants.BUILD_COMMIT
	// Make may prefix "x" when the SHA would parse as a float (7e1...).
	if len(commit) > 1 && commit[0] == 'x' {
		commit = commit[1:]
	}
	if c.narrow {
		// Keep the narrow label short: version only.
		return fmt.tprintf("? %s", constants.VERSION)
	}
	// Prefer "?  VERSION commit" when there is room; fall back to version alone
	// if the commit define is empty (dev builds without make).
	if len(commit) > 0 && c.width >= 56 {
		return fmt.tprintf("?  %s %s", constants.VERSION, commit)
	}
	return fmt.tprintf("?  %s", constants.VERSION)
}

// Mode · session counts, shortened when the bar is tight.
app_chrome_counts :: proc(a: ^App, c: Chrome, mode_chip: string) -> string {
	if c.tight {
		return mode_chip
	}
	if c.narrow {
		s := fmt.tprintf("%s · %d", mode_chip, a.banner_sess)
		if len(a.tabs) > 1 {
			s = fmt.tprintf("%s · t%d", s, len(a.tabs))
		}
		return s
	}
	s := fmt.tprintf("%s · %d sess · %d live", mode_chip, a.banner_sess, a.banner_live)
	if len(a.tabs) > 1 {
		s = fmt.tprintf("%s · %d tabs", s, len(a.tabs))
	}
	return s
}

// Provider · model · session line. Empty when there is no room.
app_chrome_right_info :: proc(a: ^App, c: Chrome, full: string) -> string {
	if c.tight || len(full) == 0 {
		return ""
	}
	if c.narrow {
		// Keep the first segment only (provider name).
		if i := strings.index_byte(full, '·'); i > 0 {
			return strings.trim_space(full[:i])
		}
	}
	return full
}

// Title bar content end column used as mid-row start after the brand.
app_draw_title_brand :: proc(buf: ^ui.Buffer, c: Chrome, t: ui.Theme) -> int {
	brand := app_chrome_brand(c)
	ui.buffer_fill_rect(buf, 0, c.title_y, buf.width, 1, ' ', t.title, t.status_bg)
	x := 1
	used := ui.draw_brand_text(buf, x, c.title_y, brand, t.status_bg, {.Bold}, t.title)
	return x + used + 1
}

// True when (mx, my) lands on the leading help glyph of the title bar.
app_help_btn_hit :: proc(a: ^App, mx, my: int) -> bool {
	if a == nil || a.help_btn_x < 0 {
		return false
	}
	w := a.help_btn_w
	if w <= 0 {
		w = 1
	}
	if my != 0 {
		return false
	}
	return mx >= a.help_btn_x && mx < a.help_btn_x + w
}
