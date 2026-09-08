// SPDX-License-Identifier: 0BSD
/*
LID harness helper tests.
*/

package agent

import "core:os"
import "core:strings"
import "core:testing"
import "nullray:provider"
import "nullray:sandbox"

@(test)
test_format_tool_envelope :: proc(t: ^testing.T) {
	s := format_tool_envelope("ok", "make test", 0, "a1", "pass", 3)
	defer delete(s)
	testing.expect(t, strings.contains(s, "status=ok"))
	testing.expect(t, strings.contains(s, "artifact=a1"))
	testing.expect(t, strings.contains(s, "--- excerpt ---"))
}

@(test)
test_offload_tool_result_stubs_large :: proc(t: ^testing.T) {
	ws := "/tmp/nullray-harness-offload-ws"
	_ = os.remove_all(ws)
	_ = os.make_directory_all(ws)
	defer os.remove_all(ws)
	st := sandbox.state()
	prev := ""
	if st != nil {
		prev = st.workspace
		st.workspace = ws
	}
	defer if st != nil {
		st.workspace = prev
	}

	os.set_env("NULLRAY_ARTIFACT_CHARS", "100")
	defer os.unset_env("NULLRAY_ARTIFACT_CHARS")

	big := strings.repeat("x", 500, context.temp_allocator)
	m: Harness_Metrics
	out := offload_tool_result("run_shell", big, "echo", false, &m)
	defer delete(out)
	testing.expect(t, m.artifacts_stored >= 1)
	testing.expect(t, strings.contains(out, "artifact="))
	testing.expect(t, strings.contains(out, "status=ok"))
}

@(test)
test_prepare_clear_writeback_style :: proc(t: ^testing.T) {
	msgs := make([dynamic]provider.Message)
	defer {
		for m in msgs {
			provider.destroy_message(m)
		}
		delete(msgs)
	}
	append(&msgs, provider.Message{role = .User, content = strings.clone("hi")})
	append(&msgs, provider.Message{role = .Tool, name = strings.clone("run_shell"), content = strings.clone(strings.repeat("Z", 200, context.temp_allocator))})
	append(&msgs, provider.Message{role = .Tool, name = strings.clone("run_shell"), content = strings.clone("keep-me")})
	n := clear_old_tool_results(&msgs, 1)
	testing.expect(t, n >= 1)
	testing.expect(t, is_cleared_tool_content(msgs[1].content) || strings.contains(msgs[1].content, "artifact=") || strings.has_prefix(msgs[1].content, "[cleared:"))
	testing.expect_value(t, msgs[2].content, "keep-me")
}

@(test)
test_projection_caps_synthetic :: proc(t: ^testing.T) {
	os.set_env("NULLRAY_ARTIFACT_CHARS", "80")
	defer os.unset_env("NULLRAY_ARTIFACT_CHARS")

	ws := "/tmp/nullray-harness-proj-ws"
	_ = os.remove_all(ws)
	_ = os.make_directory_all(ws)
	defer os.remove_all(ws)
	st := sandbox.state()
	prev := ""
	if st != nil {
		prev = st.workspace
		st.workspace = ws
	}
	defer if st != nil {
		st.workspace = prev
	}

	msgs := make([dynamic]provider.Message)
	defer {
		for m in msgs {
			provider.destroy_message(m)
		}
		delete(msgs)
	}
	fat := strings.repeat("DUMP", 200, context.temp_allocator)
	for _ in 0 ..< 20 {
		append(&msgs, provider.Message{
			role = .Tool,
			name = strings.clone("run_shell"),
			content = strings.clone(fat),
		})
	}
	before := messages_content_chars(msgs[:])
	n := clear_old_tool_results(&msgs, 4)
	testing.expect(t, n >= 10)
	after := messages_content_chars(msgs[:])
	testing.expect(t, after < before)
	testing.expect(t, after < before / 2)
}
