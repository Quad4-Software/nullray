// SPDX-License-Identifier: 0BSD
package session

import "core:testing"
import "nullray:agent"

@(test)
test_cancel_clears_pause :: proc(t: ^testing.T) {
	s: Session
	session_init(&s)
	defer session_destroy(&s)
	session_request_pause(&s)
	testing.expect(t, s.pause_requested)
	session_request_cancel(&s)
	testing.expect(t, s.cancel_requested)
	testing.expect(t, !s.pause_requested)
	testing.expect_value(t, session_stop_check(&s), agent.Stop_Kind.Cancel)
}

@(test)
test_cancel_idempotent :: proc(t: ^testing.T) {
	s: Session
	session_init(&s)
	defer session_destroy(&s)
	session_request_cancel(&s)
	session_request_cancel(&s)
	testing.expect(t, s.cancel_requested)
	testing.expect(t, !s.pause_requested)
	session_clear_control(&s)
	testing.expect(t, !s.cancel_requested)
}

@(test)
test_shutdown_idle_is_safe :: proc(t: ^testing.T) {
	s: Session
	session_init(&s)
	defer session_destroy(&s)
	session_shutdown(&s, 100)
	testing.expect(t, !s.busy)
	testing.expect(t, s.job_thread == nil)
}
