// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Turn-end distillation: fold a finished turn into one bounded store entry
and publish the tool sequence as the current trajectory tail for recall.
*/

package experience

import "core:strings"
import "core:time"
import "nullray:provider"

// req_msgs is the input message list, res_msgs the returned transcript.
// Only messages past len(req_msgs) are new, so tool history from earlier
// turns never leaks into this turn's tool sequence.
exp_record_turn :: proc(
	req_msgs, res_msgs: []provider.Message,
	ok: bool,
	stopped, err, content: string,
	escalations: int,
) {
	if !exp_enabled() {
		return
	}
	// Task signature comes from req_msgs: user-role nudges (finalize,
	// steer) appended inside the turn must not become the task.
	task := ""
	for i := len(req_msgs) - 1; i >= 0; i -= 1 {
		if req_msgs[i].role == .User {
			task = req_msgs[i].content
			break
		}
	}
	if len(task) == 0 {
		for i := len(res_msgs) - 1; i >= 0; i -= 1 {
			if res_msgs[i].role == .User {
				task = res_msgs[i].content
				break
			}
		}
	}
	if len(strings.trim_space(task)) == 0 {
		return
	}
	tools := make([dynamic]string, context.temp_allocator)
	start := min(len(req_msgs), len(res_msgs))
	for i in start ..< len(res_msgs) {
		m := res_msgs[i]
		if m.role != .Assistant {
			continue
		}
		for c in m.tool_calls {
			if len(tools) < EXP_MAX_TOOLS {
				append(&tools, c.name)
			}
		}
	}
	outcome := "ok"
	if !ok {
		outcome = "err"
	} else if stopped == "loop" || stopped == "max_steps" {
		// Anti-loop and a blown step budget are the same failure class for
		// stop rules: a trajectory that did not converge.
		outcome = "looped"
	} else if stopped == "verify_failed" || stopped == "elevate" {
		outcome = "err"
	} else if escalations > 0 {
		outcome = "escalated"
	}
	note := ""
	if len(strings.trim_space(content)) > 0 {
		note = exp_one_line(content, EXP_NOTE_CHARS, context.temp_allocator)
	} else if len(strings.trim_space(err)) > 0 {
		note = exp_one_line(err, EXP_NOTE_CHARS, context.temp_allocator)
	} else {
		note = strings.clone(stopped, context.temp_allocator)
	}
	norm := exp_normalize(task, context.temp_allocator)
	e := Exp_Entry{
		task    = strings.clone(norm, context.temp_allocator),
		sig     = exp_sig(norm, context.temp_allocator),
		tools   = tools,
		outcome = strings.clone(outcome, context.temp_allocator),
		note    = note,
		ts      = time.time_to_unix(time.now()),
	}
	_ = exp_append_entry(e)
	exp_note_tools(tools[:])
}
