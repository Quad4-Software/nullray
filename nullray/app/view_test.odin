// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package app

import "core:strings"
import "core:testing"
import "nullray:provider"

@(test)
test_collect_turn_write_paths :: proc(t: ^testing.T) {
	calls := make([]provider.Tool_Call, 3)
	calls[0] = {
		name = strings.clone("write_file"),
		arguments = strings.clone(`{"path":"a.txt","content":"x"}`),
	}
	calls[1] = {
		name = strings.clone("edit_file"),
		arguments = strings.clone(`{"path":"b.txt","old_string":"1","new_string":"2"}`),
	}
	calls[2] = {
		name = strings.clone("apply_edits"),
		arguments = strings.clone(
			`{"edits":[{"path":"c.txt","old_string":"a","new_string":"b"}],"files":[{"path":"d.txt","content":"z"}]}`,
		),
	}

	msgs := make([dynamic]provider.Message, 0, 4)
	defer {
		for m in msgs {
			provider.destroy_message(m)
		}
		delete(msgs)
	}

	append(&msgs, provider.Message{role = .User, content = strings.clone("edit please")})
	append(&msgs, provider.Message{role = .Assistant, content = strings.clone("ok"), tool_calls = calls})

	paths := collect_turn_write_paths(msgs[:])
	defer destroy_write_paths(paths)

	testing.expect(t, len(paths) >= 4)
	found_a, found_b, found_c, found_d := false, false, false, false
	for p in paths {
		if strings.contains(p, "a.txt") {
			found_a = true
		}
		if strings.contains(p, "b.txt") {
			found_b = true
		}
		if strings.contains(p, "c.txt") {
			found_c = true
		}
		if strings.contains(p, "d.txt") {
			found_d = true
		}
	}
	testing.expect(t, found_a)
	testing.expect(t, found_b)
	testing.expect(t, found_c)
	testing.expect(t, found_d)
}

@(test)
test_view_strip_hit :: proc(t: ^testing.T) {
	hits := []View_Strip_Hit{
		{i = 0, x0 = 1, x1 = 12},
		{i = 1, x0 = 15, x1 = 27},
		{i = 2, x0 = 30, x1 = 37},
	}
	testing.expect_value(t, view_strip_hit(hits, 0), -1)
	testing.expect_value(t, view_strip_hit(hits, 1), 0)
	testing.expect_value(t, view_strip_hit(hits, 11), 0)
	testing.expect_value(t, view_strip_hit(hits, 12), -1)
	testing.expect_value(t, view_strip_hit(hits, 14), -1)
	testing.expect_value(t, view_strip_hit(hits, 20), 1)
	testing.expect_value(t, view_strip_hit(hits, 37), -1)
	testing.expect_value(t, view_strip_hit(hits, 200), -1)
}

@(test)
test_view_num_w :: proc(t: ^testing.T) {
	testing.expect_value(t, view_num_w(0), 1)
	testing.expect_value(t, view_num_w(1), 1)
	testing.expect_value(t, view_num_w(9), 1)
	testing.expect_value(t, view_num_w(10), 2)
	testing.expect_value(t, view_num_w(99), 2)
	testing.expect_value(t, view_num_w(100), 3)
	testing.expect_value(t, view_num_w(9999), 4)
	testing.expect_value(t, view_num_w(10000), 5)
}

@(test)
test_view_nav_idx :: proc(t: ^testing.T) {
	testing.expect_value(t, view_nav_idx(0, 1, 3), 1)
	testing.expect_value(t, view_nav_idx(2, 1, 3), 0)
	testing.expect_value(t, view_nav_idx(0, -1, 3), 2)
	testing.expect_value(t, view_nav_idx(1, 3, 3), 1)
	testing.expect_value(t, view_nav_idx(2, 0, 3), 2)
	testing.expect_value(t, view_nav_idx(0, 1, 0), -1)
	testing.expect_value(t, view_nav_idx(7, 1, 3), 2)
}

@(test)
test_view_open_missing_shows_error :: proc(t: ^testing.T) {
	a, loop := test_app_minimal()
	_ = loop
	defer test_app_destroy_minimal(&a)
	defer app_view_destroy(&a)
	defer delete(a.session.status)
	defer delete(a.session.pending_status)
	ok := app_view_open(&a, "/nonexistent-nullray-view-test-9z7y")
	testing.expect(t, !ok)
	testing.expect(t, a.view_open)
	testing.expect(t, a.view_err)
	testing.expect_value(t, len(a.view_body), 0)
	testing.expect(t, strings.has_suffix(a.view_path, "nonexistent-nullray-view-test-9z7y"))
}
