// SPDX-License-Identifier: 0BSD
package session

import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"
import "nullray:agent"
import "nullray:provider"

@(test)
test_session_project_messages_keeps_recent :: proc(t: ^testing.T) {
	os.set_env("NULLRAY_LID", "1")
	defer os.unset_env("NULLRAY_LID")
	os.set_env("NULLRAY_PROJECTION_TURNS", "2")
	defer os.unset_env("NULLRAY_PROJECTION_TURNS")
	os.set_env("NULLRAY_PROJECTION_TOOL_STUBS", "3")
	defer os.unset_env("NULLRAY_PROJECTION_TOOL_STUBS")
	os.set_env("NULLRAY_EPHEMERAL", "1")
	defer os.unset_env("NULLRAY_EPHEMERAL")

	s: Session
	session_init(&s)
	defer session_destroy(&s)

	for i in 0 ..< 8 {
		append(&s.messages, provider.Message{
			role = .User,
			content = strings.clone(fmt.tprintf("u%d", i)),
		})
		append(&s.messages, provider.Message{
			role = .Assistant,
			content = strings.clone(fmt.tprintf("a%d", i)),
		})
	}
	for i in 0 ..< 10 {
		append(&s.messages, provider.Message{
			role = .Tool,
			name = strings.clone("run_shell"),
			tool_call_id = strings.clone(fmt.tprintf("c%d", i)),
			content = strings.clone(strings.repeat("X", 200, context.temp_allocator)),
		})
	}

	out := session_project_messages(&s)
	defer {
		for m in out {
			provider.destroy_message(m)
		}
		delete(out)
	}
	testing.expect(t, len(out) < len(s.messages))
	tool_n := 0
	for m in out {
		if m.role == .Tool {
			tool_n += 1
		}
	}
	testing.expect(t, tool_n <= 3)
}

@(test)
test_session_writeback_by_tool_call_id :: proc(t: ^testing.T) {
	os.set_env("NULLRAY_EPHEMERAL", "1")
	defer os.unset_env("NULLRAY_EPHEMERAL")

	s: Session
	session_init(&s)
	defer session_destroy(&s)

	append(&s.messages, provider.Message{
		role = .Tool,
		name = strings.clone("run_shell"),
		tool_call_id = strings.clone("id-a"),
		content = strings.clone("old-a"),
	})
	append(&s.messages, provider.Message{
		role = .Tool,
		name = strings.clone("run_shell"),
		tool_call_id = strings.clone("id-b"),
		content = strings.clone("old-b"),
	})

	flat := []provider.Message{
		{role = .Tool, name = "run_shell", tool_call_id = "id-b", content = "new-b"},
		{role = .Tool, name = "run_shell", tool_call_id = "id-a", content = "new-a"},
	}
	ok := session_writeback_prepare(&s, flat, agent.Prepare_Stats{cleared = 2})
	testing.expect(t, ok)
	testing.expect_value(t, s.messages[0].content, "new-a")
	testing.expect_value(t, s.messages[1].content, "new-b")
}

@(test)
test_session_writeback_skips_name_only :: proc(t: ^testing.T) {
	os.set_env("NULLRAY_EPHEMERAL", "1")
	defer os.unset_env("NULLRAY_EPHEMERAL")

	s: Session
	session_init(&s)
	defer session_destroy(&s)

	append(&s.messages, provider.Message{
		role = .Tool,
		name = strings.clone("run_shell"),
		tool_call_id = strings.clone("id-a"),
		content = strings.clone("old"),
	})
	flat := []provider.Message{
		{role = .Tool, name = "run_shell", content = "nope"},
	}
	ok := session_writeback_prepare(&s, flat, agent.Prepare_Stats{cleared = 1})
	testing.expect(t, !ok)
	testing.expect_value(t, s.messages[0].content, "old")
}
