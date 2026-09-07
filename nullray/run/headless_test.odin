// SPDX-License-Identifier: 0BSD
package run

import "core:testing"
import "nullray:session"

@(test)
test_print_strict_fail_timeout :: proc(t: ^testing.T) {
	s: session.Session
	session.session_init(&s)
	defer session.session_destroy(&s)
	s.agent_mode = .Ask
	s.plan_contract_ok = true

	res: Result
	res.stopped = "timeout"
	fail, reason := print_strict_fail(&s, res, 0, false)
	testing.expect(t, fail)
	testing.expect(t, len(reason) > 0)
}

@(test)
test_print_strict_fail_done_ok :: proc(t: ^testing.T) {
	s: session.Session
	session.session_init(&s)
	defer session.session_destroy(&s)
	s.agent_mode = .Ask
	s.plan_contract_ok = true

	res: Result
	res.stopped = "done"
	fail, _ := print_strict_fail(&s, res, 0, false)
	testing.expect(t, !fail)
}

@(test)
test_print_strict_fail_incomplete_plan :: proc(t: ^testing.T) {
	s: session.Session
	session.session_init(&s)
	defer session.session_destroy(&s)
	s.agent_mode = .Plan
	s.plan_contract_ok = false

	res: Result
	res.stopped = "done"
	fail, reason := print_strict_fail(&s, res, 0, false)
	testing.expect(t, fail)
	testing.expect(t, len(reason) > 0)
}

@(test)
test_print_strict_fail_living_subagents :: proc(t: ^testing.T) {
	s: session.Session
	session.session_init(&s)
	defer session.session_destroy(&s)
	s.agent_mode = .Edit
	s.plan_contract_ok = true

	res: Result
	res.stopped = "done"
	fail, reason := print_strict_fail(&s, res, 2, false)
	testing.expect(t, fail)
	testing.expect(t, len(reason) > 0)
}
