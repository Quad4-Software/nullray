// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package app

import "core:strings"
import "core:testing"

@(test)
test_collapse_preview_short_passthrough :: proc(t: ^testing.T) {
	pv, ok := collapse_preview("one\ntwo\nthree")
	testing.expect(t, !ok)
	testing.expect_value(t, pv, "")
}

@(test)
test_collapse_preview_keeps_tail :: proc(t: ^testing.T) {
	body := "l1\nl2\nl3\nl4\nl5\nl6\nl7\nl8"
	pv, ok := collapse_preview(body)
	testing.expect(t, ok)
	testing.expect(t, strings.contains(pv, "5 earlier lines"))
	testing.expect(t, strings.has_suffix(pv, "l6\nl7\nl8"))
	testing.expect(t, !strings.contains(pv, "l1"))
}

@(test)
test_block_toggle_and_expand_all :: proc(t: ^testing.T) {
	a := &App{}
	testing.expect(t, !app_block_expanded(a, "call-1"))

	app_block_toggle(a, "call-1")
	testing.expect(t, app_block_expanded(a, "call-1"))

	app_block_toggle(a, "call-1")
	testing.expect(t, !app_block_expanded(a, "call-1"))

	// expand_all flips the default, a toggled id overrides back.
	a.expand_all = true
	testing.expect(t, app_block_expanded(a, "call-9"))
	app_block_toggle(a, "call-9")
	testing.expect(t, !app_block_expanded(a, "call-9"))

	for k in a.expanded {
		delete(k)
	}
	delete(a.expanded)
}
