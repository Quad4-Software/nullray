// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package ui

import "core:testing"

@(test)
test_color_parse_hex_and_names :: proc(t: ^testing.T) {
	c, ok := color_parse("#f00")
	testing.expect(t, ok)
	testing.expect_value(t, c.r, u8(255))
	testing.expect_value(t, c.g, u8(0))
	testing.expect_value(t, c.b, u8(0))

	c2, ok2 := color_parse("#0a1b2c")
	testing.expect(t, ok2)
	testing.expect_value(t, c2.r, u8(0x0a))
	testing.expect_value(t, c2.g, u8(0x1b))
	testing.expect_value(t, c2.b, u8(0x2c))

	c3, ok3 := color_parse("cyan")
	testing.expect(t, ok3)
	testing.expect(t, c3.b > 100)

	c4, ok4 := color_parse("rgb(10, 20, 30)")
	testing.expect(t, ok4)
	testing.expect_value(t, c4.r, u8(10))
	testing.expect_value(t, c4.g, u8(20))
	testing.expect_value(t, c4.b, u8(30))

	_, bad := color_parse("not-a-color")
	testing.expect(t, !bad)
}

@(test)
test_theme_apply_colors :: proc(t: ^testing.T) {
	colors := make(map[string]string, context.temp_allocator)
	colors["accent"] = "#ff8800"
	colors["bg"] = "black"
	t2 := theme_apply_colors(INK, colors)
	testing.expect_value(t, t2.name, "custom")
	testing.expect_value(t, t2.accent.r, u8(255))
	testing.expect_value(t, t2.accent.g, u8(0x88))
	testing.expect_value(t, t2.bg.r, u8(16))
}

@(test)
test_theme_from_json :: proc(t: ^testing.T) {
	raw := `{"base":"ember","colors":{"accent":"#00ffaa","title":"yellow"}}`
	th, err := theme_from_json(raw)
	testing.expect_value(t, err, "")
	testing.expect_value(t, th.accent.g, u8(255))
	testing.expect(t, th.title.r > 200)
}
