// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Print-mode wait loop: polls a chat job to completion or timeout.
*/

package run

import "core:fmt"
import "core:os"
import "core:strings"
import "nullray:constants"
import "core:time"
import "nullray:session"
import "nullray:subagent"
import "nullray:tools"


@(private)
wait_session_chat :: proc(
	s: ^session.Session,
	rt: ^subagent.Runtime,
	deadline: time.Tick,
	timeout: time.Duration,
	timeout_sec: int,
	res: ^Result,
) -> (
	ok_done: bool,
	fatal: string,
) {
	for {
		_ = session.session_poll(s)
		if !s.busy {
			return true, ""
		}
		if time.tick_since(deadline) > timeout {
			session.session_request_cancel(s)
			// Brief wait for cancel to unblock HTTP/docs. Destroy abandons leftover workers.
			for _ in 0 ..< 40 {
				_ = session.session_poll(s)
				if !s.busy {
					break
				}
				time.sleep(50 * time.Millisecond)
			}
			delete(res.err)
			res.err = strings.clone(fmt.tprintf("timed out after %d seconds", timeout_sec))
			delete(res.stopped)
			res.stopped = strings.clone("timeout")
			res.usage = s.last_usage
			res.session_usage = s.session_usage
			res.input_chars = s.last_input_chars
			res.peak_input_chars = s.peak_input_chars
			res.usage_turns = s.usage_turns
			res.subagent_total_tokens = s.subagent_total_tokens
			text := last_assistant_text(s)
			if len(text) > 0 {
				delete(res.text)
				res.text = text
			}
			living := subagent.roster_living_count(&rt.roster)
			if living > 0 {
				fmt.eprintf("nullray: %d subagent(s) still running\n", living)
			}
			strict := false
			if v, ok := os.lookup_env(constants.ENV_PRINT_STRICT, context.temp_allocator); ok {
				switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
				case "1", "true", "yes", "on":
					strict = true
				}
			}
			if strict {
				if fail, reason := print_strict_fail(s, res^, living, false); fail {
					res.ok = false
					res.exit_code = 1
					fmt.eprintln("nullray:", reason)
					return false, "timeout"
				}
			}
			res.ok = false
			res.exit_code = 2
			return false, "timeout"
		}
		time.sleep(50 * time.Millisecond)
	}
}
