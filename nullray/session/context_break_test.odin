// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package session

import "core:strings"
import "core:testing"
import "nullray:provider"
import "nullray:tools"

@(test)
test_context_break_of_categories :: proc(t: ^testing.T) {
	s: Session
	session_init(&s)
	defer session_destroy(&s)
	s.system_prompt = strings.clone("sys")
	append(&s.messages, provider.Message{role = .User, content = strings.clone("hello world")})
	append(&s.messages, provider.Message{role = .User, content = strings.clone("<memory>lesson</memory>")})
	reg: tools.Registry
	b := context_break_of(&s, &reg)
	testing.expect(t, b.system_chars >= 3)
	testing.expect(t, b.messages_chars >= len("hello world"))
	testing.expect(t, b.memory_chars >= len("<memory>lesson</memory>"))
	text := context_breakdown_text(&s, &reg)
	defer delete(text)
	testing.expect(t, strings.contains(text, "system"))
	testing.expect(t, strings.contains(text, "tools"))
	testing.expect(t, strings.contains(text, "messages"))
	testing.expect(t, strings.contains(text, "memory"))
}
