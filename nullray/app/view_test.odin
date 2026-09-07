// SPDX-License-Identifier: 0BSD
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
