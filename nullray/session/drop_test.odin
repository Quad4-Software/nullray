// SPDX-License-Identifier: 0BSD
/*
Tests for session drop turn boundaries.
*/

package session

import "core:strings"
import "core:testing"
import "nullray:provider"

@(test)
test_drop_start_index :: proc(t: ^testing.T) {
	msgs := make([dynamic]provider.Message)
	defer {
		for m in msgs {
			provider.destroy_message(m)
		}
		delete(msgs)
	}
	append(&msgs, provider.Message{role = .User, content = strings.clone("one")})
	append(&msgs, provider.Message{role = .Assistant, content = strings.clone("a1")})
	append(&msgs, provider.Message{role = .User, content = strings.clone("two")})
	append(
		&msgs,
		provider.Message{
			role = .Assistant,
			content = strings.clone(""),
			tool_calls = []provider.Tool_Call{{id = strings.clone("1"), name = strings.clone("read_file"), arguments = strings.clone("{}")}},
		},
	)
	append(&msgs, provider.Message{role = .Tool, name = strings.clone("read_file"), content = strings.clone("out")})
	append(&msgs, provider.Message{role = .Assistant, content = strings.clone("a2")})
	append(&msgs, provider.Message{role = .User, content = strings.clone("three")})
	append(&msgs, provider.Message{role = .Assistant, content = strings.clone("a3")})

	testing.expect_value(t, drop_start_index(msgs[:], 1), 6)
	testing.expect_value(t, drop_start_index(msgs[:], 2), 2)
	testing.expect_value(t, drop_start_index(msgs[:], 3), 0)
	testing.expect_value(t, drop_start_index(msgs[:], 0), -1)
}
