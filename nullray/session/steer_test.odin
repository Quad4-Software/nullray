// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package session

import "core:strings"
import "core:testing"

@(test)
test_steer_inbox_and_followup :: proc(t: ^testing.T) {
	s: Session
	session_init(&s)
	defer session_destroy(&s)
	testing.expect(t, session_push_steer(&s, "fix the type"))
	note := session_poll_steer(&s)
	defer delete(note)
	testing.expect(t, strings.contains(note, "[steer]"))
	testing.expect(t, strings.contains(note, "fix the type"))
	testing.expect_value(t, session_poll_steer(&s), "")

	testing.expect(t, session_push_followup(&s, "then run tests"))
	q := session_take_followup(&s)
	defer delete(q)
	testing.expect_value(t, q, "then run tests")
	testing.expect_value(t, session_take_followup(&s), "")
}
