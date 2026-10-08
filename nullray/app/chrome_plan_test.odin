// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package app

import "core:testing"
import "nullray:session"
import "nullray:ui"

@(test)
test_chrome_shows_plan_strip_when_plan_steps :: proc(t: ^testing.T) {
	a, loop := test_app_minimal()
	_ = loop
	defer test_app_destroy_minimal(&a)
	ui.theme_set(ui.INK)

	// No plan -> strip off
	c0 := app_chrome(&a, 100, 30)
	testing.expect(t, !c0.show_plan || c0.plan_y < 0 || len(a.session.plan_steps) == 0)

	append(&a.session.plan_steps, "step one do the thing")
	a.session.plan_step_index = 0
	c1 := app_chrome(&a, 100, 30)
	testing.expect(t, c1.show_plan)
	testing.expect(t, c1.plan_y >= 0)

	// Tight terminal hides plan strip
	c2 := app_chrome(&a, 20, 30)
	testing.expect(t, !c2.show_plan || c2.plan_y < 0)

	// Draw should not panic
	buf := ui.buffer_create(100, 30)
	defer ui.buffer_destroy(&buf)
	app_draw_plan_strip(&buf, &a, c1)
}
