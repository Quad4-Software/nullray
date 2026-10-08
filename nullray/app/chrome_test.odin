// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package app

import "core:testing"
import "nullray:constants"
import "nullray:ui"

@(test)
test_chrome_roomy_layout :: proc(t: ^testing.T) {
	a, loop := test_app_minimal()
	_ = loop
	defer test_app_destroy_minimal(&a)

	c := app_chrome(&a, 80, 24)
	testing.expect(t, c.show_tabs)
	testing.expect(t, c.show_sep)
	testing.expect_value(t, c.title_y, 0)
	testing.expect_value(t, c.tabs_y, 1)
	testing.expect_value(t, c.sep_y, 2)
	testing.expect_value(t, c.msg_top, 3)
	testing.expect(t, c.msg_bottom >= c.msg_top)
	testing.expect(t, c.status_y > c.msg_bottom)
	testing.expect(t, c.input_y > c.status_y)
	testing.expect(t, c.input_y + c.input_rows == 24)
	testing.expect(t, app_chrome_msg_h(c) >= 1)
	testing.expect_value(t, app_chrome_brand(c), constants.APP_NAME)
	testing.expect(t, !c.narrow)
	testing.expect(t, !c.tight)
	testing.expect(t, !c.short)
}

@(test)
test_chrome_narrow_shortens_labels :: proc(t: ^testing.T) {
	a, loop := test_app_minimal()
	_ = loop
	defer test_app_destroy_minimal(&a)

	c := app_chrome(&a, 40, 24)
	testing.expect(t, c.narrow)
	testing.expect(t, !c.tight)
	testing.expect_value(t, app_chrome_brand(c), constants.APP_NAME)
	help := app_chrome_help_right(&a, c)
	testing.expect(t, len(help) < len("type / · ? help · ^q quit"))

	tight := app_chrome(&a, 20, 24)
	testing.expect(t, tight.tight)
	testing.expect_value(t, app_chrome_brand(tight), "nr")
	testing.expect_value(t, app_chrome_ver_label(tight), "?")
}

@(test)
test_chrome_short_hides_tabs :: proc(t: ^testing.T) {
	a, loop := test_app_minimal()
	_ = loop
	defer test_app_destroy_minimal(&a)

	c := app_chrome(&a, 80, 10)
	testing.expect(t, c.short)
	testing.expect(t, !c.show_tabs)
	testing.expect_value(t, c.tabs_y, -1)
	testing.expect(t, c.msg_top >= 1)
	testing.expect(t, c.input_rows <= 2)
	testing.expect(t, c.input_y + c.input_rows == 10)
	testing.expect(t, c.msg_bottom >= c.msg_top)
	testing.expect(t, c.status_y >= c.msg_bottom)
}

@(test)
test_chrome_tiny_keeps_usable_msg :: proc(t: ^testing.T) {
	a, loop := test_app_minimal()
	_ = loop
	defer test_app_destroy_minimal(&a)

	c := app_chrome(&a, 30, 6)
	testing.expect(t, c.input_rows == 1)
	testing.expect(t, app_chrome_msg_h(c) >= 1)
	testing.expect(t, c.input_y + c.input_rows == 6)
	// Status never shares the title row when height > 2.
	testing.expect(t, c.status_y != c.title_y || c.height <= 2)
	testing.expect(t, c.status_y < c.input_y || c.height <= 2)
}

@(test)
test_chrome_geometry_invariants :: proc(t: ^testing.T) {
	a, loop := test_app_minimal()
	_ = loop
	defer test_app_destroy_minimal(&a)

	sizes := [][2]int{{1, 1}, {2, 2}, {10, 3}, {20, 5}, {40, 8}, {80, 12}, {80, 24}, {200, 40}, {24, 100}}
	for s in sizes {
		c := app_chrome(&a, s[0], s[1])
		testing.expect(t, c.width == max(1, s[0]))
		testing.expect(t, c.height == max(1, s[1]))
		testing.expect(t, c.msg_bottom >= c.msg_top)
		testing.expect(t, app_chrome_msg_h(c) >= 1)
		testing.expect(t, c.input_rows >= 1)
		if c.height > 2 {
			testing.expect(t, c.status_y >= c.title_y)
			testing.expect(t, c.status_y < c.input_y || c.input_y == 0)
			testing.expect(t, c.msg_top <= c.status_y)
		}
		if c.show_tabs {
			testing.expect(t, c.tabs_y > c.title_y)
		}
		if c.show_sep {
			testing.expect(t, c.sep_y > c.title_y)
			testing.expect(t, c.sep_y < c.status_y)
		}
	}
}

@(test)
test_chrome_title_brand_draw :: proc(t: ^testing.T) {
	a, loop := test_app_minimal()
	_ = loop
	defer test_app_destroy_minimal(&a)

	ui.theme_set(ui.INK)
	buf := ui.buffer_create(40, 12)
	defer ui.buffer_destroy(&buf)
	c := app_chrome(&a, 40, 12)
	mid := app_draw_title_brand(&buf, c, ui.theme())
	testing.expect(t, mid > 1)
	testing.expect_value(t, ui.buffer_at(&buf, 1, 0).ch, 'n')
	// Gradient: first and middle letters differ.
	c0 := ui.buffer_at(&buf, 1, 0).fg
	c3 := ui.buffer_at(&buf, 4, 0).fg
	testing.expect(t, c0 != c3)
}

@(test)
test_view_layout_follows_chrome :: proc(t: ^testing.T) {
	a, loop := test_app_minimal()
	_ = loop
	defer test_app_destroy_minimal(&a)
	a.view_open = true

	lay := app_view_layout(&a, 80, 24)
	c := app_chrome(&a, 80, 24)
	testing.expect(t, lay.open)
	testing.expect_value(t, lay.pane_y, c.msg_top)
	testing.expect_value(t, lay.pane_h, app_chrome_msg_h(c))
	testing.expect(t, !lay.overlay)
	testing.expect(t, lay.pane_w >= VIEW_MIN_PANE)

	// Narrow terminal falls back to overlay.
	narrow := app_view_layout(&a, 40, 24)
	testing.expect(t, narrow.open)
	testing.expect(t, narrow.overlay)
	testing.expect_value(t, narrow.pane_w, 40)
}

@(test)
test_help_btn_hit_only_glyph :: proc(t: ^testing.T) {
	a, loop := test_app_minimal()
	_ = loop
	defer test_app_destroy_minimal(&a)
	a.help_btn_x = 70
	a.help_btn_w = 1
	testing.expect(t, app_help_btn_hit(&a, 70, 0))
	testing.expect(t, !app_help_btn_hit(&a, 71, 0))
	testing.expect(t, !app_help_btn_hit(&a, 69, 0))
	testing.expect(t, !app_help_btn_hit(&a, 70, 1))
	testing.expect(t, !app_help_btn_hit(&a, 70, -1))
}

@(test)
test_chrome_counts_compact :: proc(t: ^testing.T) {
	a, loop := test_app_minimal()
	_ = loop
	defer test_app_destroy_minimal(&a)
	a.banner_sess = 3
	a.banner_live = 1

	roomy := app_chrome(&a, 80, 24)
	full := app_chrome_counts(&a, roomy, "edit")
	testing.expect(t, len(full) > 0)

	narrow := app_chrome(&a, 40, 24)
	short := app_chrome_counts(&a, narrow, "edit")
	testing.expect(t, len(short) < len(full))

	tight := app_chrome(&a, 20, 24)
	testing.expect_value(t, app_chrome_counts(&a, tight, "edit"), "edit")
}
