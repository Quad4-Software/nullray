// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package ui

import "core:os"
import "core:testing"

@(test)
test_path_looks_like_image :: proc(t: ^testing.T) {
	testing.expect(t, path_looks_like_image("a.png"))
	testing.expect(t, path_looks_like_image("/tmp/x.JPEG"))
	testing.expect(t, !path_looks_like_image("a.txt"))
}

@(test)
test_kitty_fit_cells :: proc(t: ^testing.T) {
	c, r := kitty_fit_cells(20, 10, 100, 100)
	testing.expect(t, c <= 20)
	testing.expect(t, r <= 10)
	testing.expect(t, c >= 1)
	testing.expect(t, r >= 1)
}

@(test)
test_clipboard_sniff_png :: proc(t: ^testing.T) {
	png_hdr := []u8{0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0}
	mime, ok := clipboard_sniff_image(png_hdr)
	testing.expect(t, ok)
	testing.expect_value(t, mime, "image/png")
	_, ok2 := clipboard_sniff_image([]u8{'n', 'o', 't'})
	testing.expect(t, !ok2)
}

@(test)
test_kitty_enabled_env_off :: proc(t: ^testing.T) {
	prev, had := os.lookup_env("NULLRAY_KITTY_GRAPHICS", context.temp_allocator)
	defer if had {
		os.set_env("NULLRAY_KITTY_GRAPHICS", prev)
	} else {
		os.unset_env("NULLRAY_KITTY_GRAPHICS")
	}
	os.set_env("NULLRAY_KITTY_GRAPHICS", "0")
	testing.expect(t, !kitty_graphics_enabled())
}
