// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package session

import "core:strings"
import "core:testing"
import "nullray:provider"

@(test)
test_session_rewind_truncates_and_summarizes :: proc(t: ^testing.T) {
	s: Session
	session_init(&s)
	defer session_destroy(&s)
	s.persist = false
	append(&s.messages, provider.Message{role = .User, content = strings.clone("first")})
	append(&s.messages, provider.Message{role = .Assistant, content = strings.clone("ok")})
	append(&s.messages, provider.Message{role = .User, content = strings.clone("second")})
	append(&s.messages, provider.Message{role = .Assistant, content = strings.clone("later")})
	ok := session_rewind(&s, 1, nil)
	testing.expect(t, ok)
	testing.expect(t, len(s.messages) >= 2)
	last := s.messages[len(s.messages) - 1]
	testing.expect(t, last.role == .User)
	testing.expect(t, strings.contains(last.content, "Summarize from here"))
	testing.expect(t, strings.contains(last.content, "second") || strings.contains(last.content, "rewind"))
}
