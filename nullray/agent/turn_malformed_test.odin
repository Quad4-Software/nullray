// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package agent

import "core:strings"
import "core:testing"
import "nullray:provider"

@(test)
test_turn_drop_last_attempt :: proc(t: ^testing.T) {
	msgs := make([dynamic]provider.Message)
	defer {
		provider.destroy_messages(msgs[:])
		delete(msgs)
	}
	append(&msgs, provider.Message{role = .User, content = strings.clone("hi")})
	append(&msgs, provider.Message{role = .Assistant, content = strings.clone("call")})
	append(&msgs, provider.Message{role = .Tool, content = strings.clone("bad")})
	turn_drop_last_attempt(&msgs)
	testing.expect_value(t, len(msgs), 1)
	testing.expect(t, msgs[0].role == .User)
}

@(test)
test_malformed_restart_note :: proc(t: ^testing.T) {
	n := malformed_restart_note(.Unknown_Tool, "unknown tool: foo", true)
	defer delete(n)
	testing.expect(t, strings.contains(n, "dropped"))
	testing.expect(t, strings.contains(n, "unknown tool"))
	testing.expect(t, strings.contains(n, "Do not repeat"))
	n2 := malformed_restart_note(.Bad_Args_Json, "bad tool args JSON: x", false)
	defer delete(n2)
	testing.expect(t, strings.contains(n2, "Retry budget exhausted"))
}
