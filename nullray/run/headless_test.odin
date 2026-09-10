// SPDX-License-Identifier: 0BSD
package run

import "core:os"
import "core:strings"
import "core:testing"
import "nullray:constants"
import "nullray:provider"
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

@(test)
test_print_strict_max_steps_with_writes_ok :: proc(t: ^testing.T) {
	s: session.Session
	session.session_init(&s)
	defer session.session_destroy(&s)
	s.agent_mode = .Edit
	s.plan_contract_ok = true
	calls := make([]provider.Tool_Call, 1)
	calls[0] = provider.Tool_Call{
		id = strings.clone("1"),
		name = strings.clone("write_file"),
		arguments = strings.clone(`{"path":"a","content":"x"}`),
	}
	append(&s.messages, provider.Message{
		role = .Assistant,
		content = strings.clone("writing"),
		tool_calls = calls,
	})

	res: Result
	res.stopped = "max_steps"
	fail, _ := print_strict_fail(&s, res, 0, false)
	testing.expect(t, !fail)
}

@(test)
test_print_strict_max_steps_no_tools_fails :: proc(t: ^testing.T) {
	s: session.Session
	session.session_init(&s)
	defer session.session_destroy(&s)
	s.agent_mode = .Edit
	s.plan_contract_ok = true
	append(&s.messages, provider.Message{role = .Assistant, content = strings.clone("thinking")})

	res: Result
	res.stopped = "max_steps"
	fail, reason := print_strict_fail(&s, res, 0, false)
	testing.expect(t, fail)
	testing.expect(t, len(reason) > 0)
}

@(test)
test_print_strict_max_steps_verify_failed_still_fails :: proc(t: ^testing.T) {
	s: session.Session
	session.session_init(&s)
	defer session.session_destroy(&s)
	s.agent_mode = .Edit
	s.plan_contract_ok = true
	s.verify_fail_count = 1
	calls := make([]provider.Tool_Call, 1)
	calls[0] = provider.Tool_Call{
		id = strings.clone("1"),
		name = strings.clone("write_file"),
		arguments = strings.clone(`{"path":"a","content":"x"}`),
	}
	append(&s.messages, provider.Message{
		role = .Assistant,
		content = strings.clone("writing"),
		tool_calls = calls,
	})

	res: Result
	res.stopped = "max_steps"
	fail, reason := print_strict_fail(&s, res, 0, false)
	testing.expect(t, fail)
	testing.expect(t, len(reason) > 0)
}

@(test)
test_print_strict_verify_skipped_after_writes_fails :: proc(t: ^testing.T) {
	prev, had := os.lookup_env(constants.ENV_VERIFY, context.allocator)
	os.set_env(constants.ENV_VERIFY, "1")
	defer {
		if had {
			os.set_env(constants.ENV_VERIFY, prev)
		} else {
			os.unset_env(constants.ENV_VERIFY)
		}
		delete(prev)
	}

	s: session.Session
	session.session_init(&s)
	defer session.session_destroy(&s)
	s.agent_mode = .Edit
	s.plan_contract_ok = true
	s.verify_ran = false
	calls := make([]provider.Tool_Call, 1)
	calls[0] = provider.Tool_Call{
		id = strings.clone("1"),
		name = strings.clone("write_file"),
		arguments = strings.clone(`{"path":"a","content":"x"}`),
	}
	append(&s.messages, provider.Message{
		role = .Assistant,
		content = strings.clone("writing"),
		tool_calls = calls,
	})

	res: Result
	res.stopped = "done"
	fail, reason := print_strict_fail(&s, res, 0, false)
	testing.expect(t, fail)
	testing.expect(t, strings.contains(reason, "verify did not run"))
}
