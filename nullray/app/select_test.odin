// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package app

import "core:strings"
import "core:testing"
import "nullray:ui"

@(test)
test_sel_extract_drag_range :: proc(t: ^testing.T) {
	a: App
	a.sel_rows = make([dynamic]string)
	defer app_sel_destroy(&a)
	a.sel_rows_top = 2
	append(&a.sel_rows, strings.clone("hello world"))
	append(&a.sel_rows, strings.clone("second line"))
	a.sel_has = true
	a.sel_ax = 0
	a.sel_ay = 2
	a.sel_bx = 4
	a.sel_by = 2
	out := app_sel_extract(&a, context.allocator)
	defer delete(out)
	testing.expect(t, strings.has_prefix(out, "hello") || strings.contains(out, "hell"))
}

@(test)
test_sel_extract_message_click_fallback :: proc(t: ^testing.T) {
	a: App
	a.sel_rows = make([dynamic]string)
	defer app_sel_destroy(&a)
	a.sel_rows_top = 0
	append(&a.sel_rows, strings.clone("alpha"))
	append(&a.sel_rows, strings.clone("beta"))
	a.sel_has = true
	a.sel_ax = 0
	a.sel_ay = 0
	a.sel_bx = 100
	a.sel_by = 1
	out := app_sel_extract(&a, context.allocator)
	defer delete(out)
	testing.expect(t, strings.contains(out, "alpha"))
	testing.expect(t, strings.contains(out, "beta"))
}

@(test)
test_sel_copy_empty_warns_false :: proc(t: ^testing.T) {
	a, loop := test_app_minimal()
	_ = loop
	defer test_app_destroy_minimal(&a)
	a.sel_has = true
	a.sel_rows_top = 0
	// no rows -> nothing selected
	ok := app_sel_copy(&a)
	testing.expect(t, !ok)
}
