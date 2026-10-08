// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package ui

import "core:os"
import "core:strings"
import "core:testing"

@(test)
test_theme_export_json_is_valid :: proc(t: ^testing.T) {
	th := theme_by_name("ember")
	js := theme_export_json(th, context.allocator)
	defer delete(js)
	testing.expect(t, !strings.contains(js, "%!("))
	testing.expect(t, strings.has_prefix(js, "{"))
	testing.expect(t, strings.contains(js, `"accent"`))
	testing.expect(t, strings.contains(js, `"name"`))
	loaded, perr := theme_from_json(js)
	testing.expect_value(t, perr, "")
	testing.expect(t, loaded.accent.r == th.accent.r)
	testing.expect(t, loaded.accent.g == th.accent.g)
	testing.expect(t, loaded.accent.b == th.accent.b)
}

@(test)
test_theme_persist_roundtrip :: proc(t: ^testing.T) {
	// Use a unique name via colors so we do not clobber a user file permanently:
	// save moss, load, restore previous if any.
	path := theme_custom_path(context.temp_allocator)
	prev, perr := os.read_entire_file(path, context.temp_allocator)
	had_prev := perr == nil && len(prev) > 0
	th := theme_by_name("moss")
	ok, err := theme_persist(th)
	testing.expect_value(t, err, "")
	testing.expect(t, ok)
	loaded, lok := theme_load_custom()
	testing.expect(t, lok)
	testing.expect(t, loaded.accent.r == th.accent.r)
	testing.expect(t, loaded.bg.r == th.bg.r)
	if had_prev {
		_ = os.write_entire_file(path, prev)
	} else {
		_ = theme_clear_custom()
	}
}

@(test)
test_theme_load_rejects_corrupt_export :: proc(t: ^testing.T) {
	path := theme_custom_path(context.temp_allocator)
	prev, perr := os.read_entire_file(path, context.temp_allocator)
	had_prev := perr == nil && len(prev) > 0
	bad := `%!(MISSING CLOSE BRACE)name":"ember"`
	_ = os.write_entire_file(path, transmute([]u8)bad)
	_, lok := theme_load_custom()
	testing.expect(t, !lok)
	if had_prev {
		_ = os.write_entire_file(path, prev)
	} else {
		_ = theme_clear_custom()
	}
}
