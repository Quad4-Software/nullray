// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Failed-call echo prevention (arxiv 2608.23651). Replaying a verbatim
failed tool call makes weak models re-emit it, so the recorded assistant
tool_call loses its raw arguments and any surface echo. The attempt stays
in the transcript as a description, deleting it would just restore the
failure-inducing context.
*/

package agent

import "core:strings"
import "nullray:provider"

// Replacement arguments for a recorded call that failed. Still a JSON
// object so provider serializers keep working.
FAILED_CALL_ARGS :: `{"_failed":true}`

/*
Scrub the recorded assistant tool_call that matches c. Keeps id and name
so the tool_call_id pairing stays intact, drops the raw arguments and any
verbatim echo of them in the assistant content.
*/
scrub_failed_call_args :: proc(msgs: ^[dynamic]provider.Message, c: provider.Tool_Call, allocator := context.allocator) {
	if msgs == nil {
		return
	}
	for i := len(msgs) - 1; i >= 0; i -= 1 {
		m := &msgs[i]
		if m.role != .Assistant {
			continue
		}
		hit := false
		for tc, j in m.tool_calls {
			matched := false
			if len(c.id) > 0 {
				matched = tc.id == c.id
			} else {
				matched = tc.name == c.name && tc.arguments == c.arguments
			}
			if matched {
				delete(tc.arguments)
				m.tool_calls[j].arguments = strings.clone(FAILED_CALL_ARGS, allocator)
				hit = true
			}
		}
		if hit {
			scrub_failed_call_surface(m, c, allocator)
			return
		}
	}
}

/*
Text-parsed calls leave the raw call JSON in the assistant content. Cut
the verbatim arguments and, when the whole message was the call surface,
replace it with a note.
*/
@(private)
scrub_failed_call_surface :: proc(m: ^provider.Message, c: provider.Tool_Call, allocator := context.allocator) {
	if len(c.arguments) == 0 || !strings.contains(m.content, c.arguments) {
		return
	}
	next, _ := strings.replace_all(m.content, c.arguments, "(arguments withheld)", context.temp_allocator)
	if strings.contains(next, `"arguments"`) && strings.contains(next, c.name) {
		delete(m.content)
		m.content = strings.clone("(failed tool call surface withheld)", allocator)
		return
	}
	delete(m.content)
	m.content = strings.clone(next, allocator)
}
