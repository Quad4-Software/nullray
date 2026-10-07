// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package app

import "core:strings"
import "core:testing"
import "nullray:provider"
import "nullray:ui"

@(test)
test_history_lines_roles_and_labels :: proc(t: ^testing.T) {
	ui.theme_set(ui.INK)
	msgs := []provider.Message{
		{role = .User, content = "hello"},
		{role = .Assistant, content = "hi there"},
		{role = .Tool, name = "shell", content = "out"},
	}
	lines := history_view_lines(msgs, 40, "", "", ui.theme(), ui.INK.accent)

	found_you, found_nullray, found_tool := false, false, false
	for ln in lines {
		if ln.text == "you" {
			found_you = true
			testing.expect(t, .Bold in ln.style)
		}
		if ln.text == "nullray" {
			found_nullray = true
		}
		if ln.text == "tool:shell" {
			found_tool = true
		}
	}
	testing.expect(t, found_you)
	testing.expect(t, found_nullray)
	testing.expect(t, found_tool)
}

@(test)
test_history_lines_reasoning_dim :: proc(t: ^testing.T) {
	ui.theme_set(ui.INK)
	msgs := []provider.Message{
		{role = .Assistant, content = "answer", reasoning = "secret chain of thought"},
	}
	lines := history_view_lines(msgs, 40, "", "", ui.theme(), ui.INK.accent)

	found_think, found_reason := false, false
	for ln in lines {
		if ln.text == "think:" {
			found_think = true
			testing.expect(t, .Dim in ln.style)
		}
		if strings.contains(ln.text, "chain of thought") {
			found_reason = true
			testing.expect(t, .Dim in ln.style)
			testing.expect_value(t, ln.fg, ui.INK.muted)
		}
	}
	testing.expect(t, found_think)
	testing.expect(t, found_reason)
}

@(test)
test_history_lines_wrap_narrow :: proc(t: ^testing.T) {
	ui.theme_set(ui.INK)
	msgs := []provider.Message{
		{role = .User, content = "aaaa bbbb cccc dddd eeee ffff"},
	}
	lines := history_view_lines(msgs, 12, "", "", ui.theme(), ui.INK.accent)
	// Label plus several wrapped rows.
	testing.expect(t, len(lines) >= 3)
	for ln in lines {
		testing.expect(t, ui.string_cols(ln.text) <= 12)
	}
}

@(test)
test_history_lines_live_thinking_and_stream :: proc(t: ^testing.T) {
	ui.theme_set(ui.INK)
	lines := history_view_lines(
		nil,
		40,
		"pondering deeply",
		"partial reply",
		ui.theme(),
		ui.INK.accent,
	)
	found_think, found_stream := false, false
	for ln in lines {
		if ln.text == "pondering deeply" {
			found_think = true
			testing.expect(t, .Dim in ln.style)
		}
		if ln.text == "partial reply" {
			found_stream = true
			testing.expect(t, !(.Dim in ln.style))
		}
	}
	testing.expect(t, found_think)
	testing.expect(t, found_stream)
}

@(test)
test_history_lines_empty :: proc(t: ^testing.T) {
	ui.theme_set(ui.INK)
	lines := history_view_lines(nil, 40, "", "", ui.theme(), ui.INK.accent)
	testing.expect_value(t, len(lines), 0)
}
