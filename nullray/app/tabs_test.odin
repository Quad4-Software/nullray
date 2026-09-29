// SPDX-License-Identifier: 0BSD
package app

import "core:testing"
import "nullray:session"
import "nullray:ui"

@(test)
test_tab_goto_switches_active_session :: proc(t: ^testing.T) {
	a, loop := test_app_minimal()
	_ = loop
	defer test_app_destroy_minimal(&a)
	session.session_init(a.session)
	defer session.session_destroy(a.session)

	s2 := new(session.Session)
	session.session_init(s2)
	defer session.session_destroy(s2)
	append(&a.tabs, Tab{sess = s2})

	app_tab_goto(&a, 1)
	testing.expect(t, a.session == s2)
	testing.expect_value(t, a.active_tab, 1)

	app_tab_cycle(&a, 1)
	testing.expect_value(t, a.active_tab, 0)
	testing.expect(t, a.session == a.tabs[0].sess)

	app_tab_cycle(&a, -1)
	testing.expect_value(t, a.active_tab, 1)
}

@(test)
test_tab_at_x_hit_map :: proc(t: ^testing.T) {
	a, loop := test_app_minimal()
	_ = loop
	defer test_app_destroy_minimal(&a)
	a.session.name = "alpha"
	s2 := new(session.Session)
	s2.name = "beta"
	append(&a.tabs, Tab{sess = s2})

	testing.expect_value(t, app_tab_at_x(&a, 1), 0)
	testing.expect_value(t, app_tab_at_x(&a, 4), 0)
	testing.expect_value(t, app_tab_at_x(&a, 9), 1)
	testing.expect_value(t, app_tab_at_x(&a, 60), -1)
}

@(test)
test_tab_strip_draw_smoke :: proc(t: ^testing.T) {
	a, loop := test_app_minimal()
	_ = loop
	defer test_app_destroy_minimal(&a)
	a.session.name = "one"
	s2 := new(session.Session)
	s2.name = "two"
	append(&a.tabs, Tab{sess = s2})

	ui.theme_set(ui.INK)
	buf := ui.buffer_create(80, 24)
	defer ui.buffer_destroy(&buf)
	app_draw_tabs(&buf, &a, 1)
}

@(test)
test_tab_busy_indicator_updates :: proc(t: ^testing.T) {
	a, loop := test_app_minimal()
	_ = loop
	defer test_app_destroy_minimal(&a)
	session.session_init(a.session)
	defer session.session_destroy(a.session)
	s2 := new(session.Session)
	session.session_init(s2)
	defer session.session_destroy(s2)
	append(&a.tabs, Tab{sess = s2})

	s2.busy = true
	a.active_tab = 0
	changed := app_poll_tabs(&a)
	testing.expect(t, changed)
	testing.expect(t, a.tabs[1].busy_before)

	s2.busy = false
	_ = app_poll_tabs(&a)
	testing.expect(t, a.tabs[1].done_pending)
	testing.expect(t, !a.tabs[0].done_pending)
}
