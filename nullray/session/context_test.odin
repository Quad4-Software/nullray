// SPDX-License-Identifier: 0BSD
/*
Tests for tool-result clearing helpers.
*/

package session

import "core:strings"
import "core:testing"
import "nullray:constants"
import "nullray:provider"

@(test)
test_clear_old_tool_results :: proc(t: ^testing.T) {
	msgs := make([dynamic]provider.Message)
	defer {
		for m in msgs {
			provider.destroy_message(m)
		}
		delete(msgs)
	}
	append(&msgs, provider.Message{role = .User, content = strings.clone("hi")})
	append(&msgs, provider.Message{role = .Tool, name = strings.clone("read_file"), content = strings.clone("AAAA")})
	append(&msgs, provider.Message{role = .Tool, name = strings.clone("read_file"), content = strings.clone("BBBB")})
	append(&msgs, provider.Message{role = .Tool, name = strings.clone("read_file"), content = strings.clone("CCCC")})
	n := clear_old_tool_results(&msgs, 1)
	testing.expect(t, n >= 1)
	testing.expect(t, strings.has_prefix(msgs[1].content, constants.TOOL_CLEAR_STUB_PREFIX) || strings.has_prefix(msgs[2].content, constants.TOOL_CLEAR_STUB_PREFIX))
	testing.expect_value(t, msgs[3].content, "CCCC")
}
