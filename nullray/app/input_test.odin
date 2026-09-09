// SPDX-License-Identifier: 0BSD
package app

import "core:strings"
import "core:testing"
import "nullray:config"
import "nullray:constants"
import "nullray:provider"
import "nullray:session"
import "nullray:ui"

@(private)
test_app_minimal :: proc() -> (a: App, loop: ui.Loop) {
	loop = {}
	loop.term.width = 80
	loop.term.height = 24
	a = {}
	a.loop = &loop
	strings.builder_init(&a.input)
	a.binds = config.binds_defaults()
	a.follow = true
	a.view_auto = true
	return
}

@(private)
test_app_destroy_minimal :: proc(a: ^App) {
	strings.builder_destroy(&a.input)
	app_toasts_destroy(a)
	app_expand_hits_clear(a)
	delete(a.expand_hits)
	delete(a.improve_undo)
	delete(a.improve_pending_text)
	delete(a.improve_pending_err)
	delete(a.status_body)
}

@(private)
oracle_input :: proc(t: ^testing.T, a: ^App) {
	text := strings.to_string(a.input)
	testing.expect(t, a.cursor >= 0 && a.cursor <= len(text))
	testing.expect(t, ui.is_rune_boundary(text, a.cursor))
	testing.expect(t, len(text) <= constants.MAX_INPUT_CHARS)
}

@(test)
test_input_utf8_arrows_backspace :: proc(t: ^testing.T) {
	a, loop := test_app_minimal()
	_ = loop
	defer test_app_destroy_minimal(&a)

	_ = app_on_event(ui.Event{kind = .Rune, ch = 'a'}, &a)
	_ = app_on_event(ui.Event{kind = .Rune, ch = '世'}, &a)
	_ = app_on_event(ui.Event{kind = .Rune, ch = 'b'}, &a)
	oracle_input(t, &a)
	testing.expect_value(t, strings.to_string(a.input), "a世b")
	testing.expect_value(t, a.cursor, len("a世b"))

	_ = app_on_event(ui.Event{kind = .Left}, &a)
	testing.expect_value(t, a.cursor, len("a世"))
	_ = app_on_event(ui.Event{kind = .Left}, &a)
	testing.expect_value(t, a.cursor, 1)
	_ = app_on_event(ui.Event{kind = .Backspace}, &a)
	testing.expect_value(t, strings.to_string(a.input), "世b")
	oracle_input(t, &a)
}

@(test)
test_input_delete_forward_rune :: proc(t: ^testing.T) {
	a, loop := test_app_minimal()
	_ = loop
	defer test_app_destroy_minimal(&a)
	app_insert_text(&a, "a世b")
	a.cursor = 1
	_ = app_on_event(ui.Event{kind = .Delete}, &a)
	testing.expect_value(t, strings.to_string(a.input), "ab")
	oracle_input(t, &a)
}

@(test)
test_input_paste_truncate :: proc(t: ^testing.T) {
	a, loop := test_app_minimal()
	_ = loop
	defer test_app_destroy_minimal(&a)
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	for _ in 0 ..< (constants.MAX_INPUT_CHARS + 100) {
		strings.write_byte(&b, 'x')
	}
	app_insert_text(&a, strings.to_string(b))
	testing.expect_value(t, len(strings.to_string(a.input)), constants.MAX_INPUT_CHARS)
	oracle_input(t, &a)
	testing.expect(t, len(a.toasts) > 0)
}

@(test)
test_stop_agent_bind_cancels :: proc(t: ^testing.T) {
	a, loop := test_app_minimal()
	_ = loop
	defer test_app_destroy_minimal(&a)
	session.session_init(&a.session)
	defer session.session_destroy(&a.session)
	a.session.busy = true
	a.session.pause_requested = true
	a.pasting = true
	_ = app_on_event(ui.Event{kind = .Esc}, &a)
	testing.expect(t, a.session.cancel_requested)
	testing.expect(t, !a.session.pause_requested)
	testing.expect(t, !a.pasting)
}

@(test)
test_ctrl_c_busy_soft_stops :: proc(t: ^testing.T) {
	a, loop := test_app_minimal()
	_ = loop
	defer test_app_destroy_minimal(&a)
	session.session_init(&a.session)
	defer session.session_destroy(&a.session)
	a.session.busy = true
	quit := app_on_event(ui.Event{kind = .Ctrl_C}, &a)
	testing.expect(t, !quit)
	testing.expect(t, a.session.cancel_requested)
}

@(test)
test_ctrl_c_idle_quits :: proc(t: ^testing.T) {
	a, loop := test_app_minimal()
	_ = loop
	defer test_app_destroy_minimal(&a)
	session.session_init(&a.session)
	defer session.session_destroy(&a.session)
	a.session.busy = false
	quit := app_on_event(ui.Event{kind = .Ctrl_C}, &a)
	testing.expect(t, quit)
}

@(test)
test_clear_chat_blocked_when_busy :: proc(t: ^testing.T) {
	a, loop := test_app_minimal()
	_ = loop
	defer test_app_destroy_minimal(&a)
	session.session_init(&a.session)
	defer session.session_destroy(&a.session)
	a.session.busy = true
	before := len(a.session.messages)
	append(&a.session.messages, provider.Message{role = .User, content = strings.clone("keep")})
	testing.expect_value(t, len(a.session.messages), before + 1)
	_ = app_on_event(ui.Event{kind = .Ctrl_L}, &a)
	testing.expect_value(t, len(a.session.messages), before + 1)
}

@(test)
test_suggest_esc_keeps_input :: proc(t: ^testing.T) {
	a, loop := test_app_minimal()
	_ = loop
	defer test_app_destroy_minimal(&a)
	app_insert_text(&a, "/he")
	_ = app_on_event(ui.Event{kind = .Esc}, &a)
	testing.expect_value(t, strings.to_string(a.input), "/he")
}

@(test)
test_tool_artifact_stub_oracle :: proc(t: ^testing.T) {
	stub, ok := tool_artifact_stub("status=ok artifact=abc_12\nexcerpt", context.temp_allocator)
	testing.expect(t, ok)
	testing.expect(t, strings.contains(stub, "/artifact abc_12"))
	_, bad := tool_artifact_stub("no id here", context.temp_allocator)
	testing.expect(t, !bad)
}

@(test)
test_input_fuzz_events :: proc(t: ^testing.T) {
	a, loop := test_app_minimal()
	_ = loop
	defer test_app_destroy_minimal(&a)
	runes := []rune{'a', 'b', '世', 'é', '\n', 'x'}
	seed: u64 = 42
	for i in 0 ..< 200 {
		seed = seed * 1103515245 + 12345
		op := int(seed % 6)
		switch op {
		case 0:
			ch := runes[int((seed / 7) % u64(len(runes)))]
			_ = app_on_event(ui.Event{kind = .Rune, ch = ch}, &a)
		case 1:
			_ = app_on_event(ui.Event{kind = .Left}, &a)
		case 2:
			_ = app_on_event(ui.Event{kind = .Right}, &a)
		case 3:
			_ = app_on_event(ui.Event{kind = .Backspace}, &a)
		case 4:
			_ = app_on_event(ui.Event{kind = .Delete}, &a)
		case 5:
			app_insert_text(&a, "yz")
		}
		_ = i
		oracle_input(t, &a)
	}
}

@(test)
test_draw_input_box_multiline :: proc(t: ^testing.T) {
	ui.theme_set(ui.INK)
	a, loop := test_app_minimal()
	_ = loop
	defer test_app_destroy_minimal(&a)
	app_insert_text(&a, "line1\nline2")
	b := ui.buffer_create(40, 10)
	defer ui.buffer_destroy(&b)
	app_draw_input_box(&b, &a, 7, 2, ui.INK.fg, ui.INK.input_bg, ui.INK.accent)
	testing.expect(t, app_input_rows(&a, 40) >= 2)
}
