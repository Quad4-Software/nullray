// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
AgentDiet rule tests: re-read dedup, superseded search, shell repeats,
exact duplicates, stale truncation, never-diet guards, pairing.
*/

package agent

import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"
import "nullray:provider"

@(private)
diet_call :: proc(id, name, args: string) -> provider.Tool_Call {
	return provider.Tool_Call{
		id = strings.clone(id),
		name = strings.clone(name),
		arguments = strings.clone(args),
	}
}

@(private)
diet_asst :: proc(content: string, calls: ..provider.Tool_Call) -> provider.Message {
	m := provider.Message{role = .Assistant, content = strings.clone(content)}
	if len(calls) > 0 {
		arr := make([]provider.Tool_Call, len(calls))
		for c, i in calls {
			arr[i] = c
		}
		m.tool_calls = arr
	}
	return m
}

@(private)
diet_tool :: proc(id, name, content: string) -> provider.Message {
	return provider.Message{
		role = .Tool,
		content = strings.clone(content),
		tool_call_id = strings.clone(id),
		name = strings.clone(name),
	}
}

@(private)
diet_destroy :: proc(msgs: [dynamic]provider.Message) {
	for m in msgs {
		provider.destroy_message(m)
	}
	delete(msgs)
}

@(test)
test_diet_reread_keeps_latest :: proc(t: ^testing.T) {
	os.set_env("NULLRAY_CORVUS", "0")
	defer os.unset_env("NULLRAY_CORVUS")
	msgs := make([dynamic]provider.Message)
	defer diet_destroy(msgs)
	append(&msgs, provider.Message{role = .System, content = strings.clone("sys")})
	append(&msgs, provider.Message{role = .User, content = strings.clone("task")})
	append(&msgs, diet_asst("", diet_call("c1", "read_file", `{"path":"/src/a.odin"}`)))
	append(&msgs, diet_tool("c1", "read_file", strings.repeat("OLD", 500, context.temp_allocator)))
	append(&msgs, diet_asst("", diet_call("c2", "read_file", `{"path":"/src/a.odin"}`)))
	append(&msgs, diet_tool("c2", "read_file", strings.repeat("NEW", 500, context.temp_allocator)))
	append(&msgs, diet_asst("done"))

	d, st := diet_messages(msgs[:])
	defer diet_destroy(d)
	testing.expect_value(t, st.stubbed, 1)
	testing.expect(t, strings.has_prefix(d[3].content, DIET_STUB_PREFIX))
	testing.expect(t, strings.contains(d[3].content, "/src/a.odin"))
	testing.expect(t, strings.contains(d[5].content, "NEW"))
	testing.expect_value(t, d[3].tool_call_id, "c1")
	testing.expect_value(t, d[5].tool_call_id, "c2")
	// Original list untouched.
	testing.expect(t, strings.contains(msgs[3].content, "OLD"))
}

@(test)
test_diet_write_then_read_supersedes :: proc(t: ^testing.T) {
	msgs := make([dynamic]provider.Message)
	defer diet_destroy(msgs)
	append(&msgs, provider.Message{role = .User, content = strings.clone("task")})
	append(&msgs, diet_asst("", diet_call("c1", "write_file", `{"path":"/src/b.odin"}`)))
	append(&msgs, diet_tool("c1", "write_file", "status=ok wrote 120 bytes"))
	append(&msgs, diet_asst("", diet_call("c2", "read_file", `{"path":"/src/b.odin"}`)))
	append(&msgs, diet_tool("c2", "read_file", "fresh body"))
	append(&msgs, diet_asst("done"))

	d, st := diet_messages(msgs[:])
	defer diet_destroy(d)
	testing.expect_value(t, st.stubbed, 1)
	testing.expect(t, strings.has_prefix(d[2].content, DIET_STUB_PREFIX))
	testing.expect_value(t, d[4].content, "fresh body")
}

@(test)
test_diet_search_superseded_by_fetch :: proc(t: ^testing.T) {
	msgs := make([dynamic]provider.Message)
	defer diet_destroy(msgs)
	append(&msgs, provider.Message{role = .User, content = strings.clone("q")})
	append(&msgs, diet_asst("", diet_call("c1", "web_search", `{"query":"odin strings"}`)))
	append(&msgs, diet_tool("c1", "web_search", "1. docs https://example.com/odin/strings\n2. other"))
	append(&msgs, diet_asst("", diet_call("c2", "fetch_url", `{"url":"https://example.com/odin/strings"}`)))
	append(&msgs, diet_tool("c2", "fetch_url", "full page text"))
	append(&msgs, diet_asst("done"))

	d, st := diet_messages(msgs[:])
	defer diet_destroy(d)
	testing.expect_value(t, st.stubbed, 1)
	testing.expect(t, strings.has_prefix(d[2].content, DIET_STUB_PREFIX))
	testing.expect(t, strings.contains(d[4].content, "full page text"))
}

@(test)
test_diet_shell_repeat_keeps_last :: proc(t: ^testing.T) {
	msgs := make([dynamic]provider.Message)
	defer diet_destroy(msgs)
	append(&msgs, provider.Message{role = .User, content = strings.clone("t")})
	append(&msgs, diet_asst("", diet_call("c1", "run_shell", `{"command":"make"}`)))
	append(&msgs, diet_tool("c1", "run_shell", "build log v1"))
	append(&msgs, diet_asst("", diet_call("c2", "run_shell", `{"command":"make"}`)))
	append(&msgs, diet_tool("c2", "run_shell", "build log v2"))
	append(&msgs, diet_asst("done"))

	d, st := diet_messages(msgs[:])
	defer diet_destroy(d)
	testing.expect_value(t, st.stubbed, 1)
	testing.expect(t, strings.has_prefix(d[2].content, DIET_STUB_PREFIX))
	testing.expect_value(t, d[4].content, "build log v2")
}

@(test)
test_diet_identical_results_keep_first :: proc(t: ^testing.T) {
	msgs := make([dynamic]provider.Message)
	defer diet_destroy(msgs)
	append(&msgs, provider.Message{role = .User, content = strings.clone("t")})
	append(&msgs, diet_asst("", diet_call("c1", "grep_files", `{"pattern":"TODO"}`)))
	append(&msgs, diet_tool("c1", "grep_files", "hit a:1\nhit b:2"))
	append(&msgs, diet_asst("", diet_call("c2", "grep_files", `{"pattern":"TODO"}`)))
	append(&msgs, diet_tool("c2", "grep_files", "hit a:1\nhit b:2"))
	append(&msgs, diet_asst("", diet_call("c3", "run_shell", `{"command":"ls"}`)))
	append(&msgs, diet_tool("c3", "run_shell", "files"))
	append(&msgs, diet_asst("done"))

	d, st := diet_messages(msgs[:])
	defer diet_destroy(d)
	testing.expect_value(t, st.stubbed, 1)
	testing.expect_value(t, d[2].content, "hit a:1\nhit b:2")
	testing.expect(t, strings.has_prefix(d[4].content, DIET_STUB_PREFIX))
	testing.expect_value(t, d[4].tool_call_id, "c2")
}

@(test)
test_diet_stale_truncates_old_long_output :: proc(t: ^testing.T) {
	msgs := make([dynamic]provider.Message)
	defer diet_destroy(msgs)
	append(&msgs, provider.Message{role = .User, content = strings.clone("t")})
	append(&msgs, diet_asst("", diet_call("c0", "run_shell", `{"command":"dump A"}`)))
	big := strings.concatenate({strings.repeat("H", 800, context.temp_allocator), strings.repeat("M", 800, context.temp_allocator), strings.repeat("T", 800, context.temp_allocator)}, context.temp_allocator)
	append(&msgs, diet_tool("c0", "run_shell", big))
	// Enough distinct tool results after so the big one goes stale.
	for i in 0 ..< 9 {
		id := fmt.tprintf("s%d", i)
		cmd := fmt.tprintf(`{"command":"cmd-%d"}`, i)
		append(&msgs, diet_asst("", diet_call(id, "run_shell", cmd)))
		append(&msgs, diet_tool(id, "run_shell", fmt.tprintf("out %d", i)))
	}
	append(&msgs, diet_asst("done"))

	d, st := diet_messages(msgs[:])
	defer diet_destroy(d)
	testing.expect(t, st.truncated >= 1)
	testing.expect(t, strings.contains(d[2].content, DIET_ELIDED_MARK))
	testing.expect(t, strings.has_prefix(d[2].content, strings.repeat("H", 20, context.temp_allocator)))
	testing.expect(t, len(d[2].content) < len(big))
	testing.expect_value(t, d[2].tool_call_id, "c0")
}

@(test)
test_diet_never_guards :: proc(t: ^testing.T) {
	os.set_env("NULLRAY_CORVUS", "0")
	defer os.unset_env("NULLRAY_CORVUS")
	msgs := make([dynamic]provider.Message)
	defer diet_destroy(msgs)
	append(&msgs, provider.Message{role = .System, content = strings.clone("sys")})
	append(&msgs, provider.Message{role = .User, content = strings.clone("original request")})
	append(&msgs, diet_asst("", diet_call("c1", "read_file", `{"path":"/x.odin"}`)))
	append(&msgs, diet_tool("c1", "read_file", "body one"))
	append(&msgs, diet_asst("", diet_call("c2", "read_file", `{"path":"/x.odin"}`)))
	// Last assistant text references the path, so both results stay.
	append(&msgs, diet_tool("c2", "read_file", "body two"))
	append(&msgs, diet_asst("I will now edit /x.odin next"))

	d, st := diet_messages(msgs[:])
	defer diet_destroy(d)
	// Empty result means the plan found nothing safe to prune.
	testing.expect_value(t, st.stubbed, 0)
	testing.expect_value(t, len(d), 0)
	testing.expect_value(t, msgs[1].content, "original request")
	testing.expect_value(t, msgs[3].content, "body one")

	// Duplicates: keep first, stub rest, except a copy inside the last two.
	msgs2 := make([dynamic]provider.Message)
	defer diet_destroy(msgs2)
	append(&msgs2, diet_asst("",
		diet_call("d1", "grep_files", `{"pattern":"zz"}`),
		diet_call("d2", "grep_files", `{"pattern":"zz"}`),
		diet_call("d3", "grep_files", `{"pattern":"zz"}`)))
	append(&msgs2, diet_tool("d1", "grep_files", "same body"))
	append(&msgs2, diet_tool("d2", "grep_files", "same body"))
	append(&msgs2, diet_tool("d3", "grep_files", "same body"))
	append(&msgs2, diet_asst("tail"))
	d2, st2 := diet_messages(msgs2[:])
	defer diet_destroy(d2)
	testing.expect_value(t, st2.stubbed, 1)
	testing.expect_value(t, d2[1].content, "same body")
	testing.expect(t, strings.has_prefix(d2[2].content, DIET_STUB_PREFIX))
	testing.expect_value(t, d2[3].content, "same body")
	testing.expect_value(t, d2[4].content, "tail")
}

@(test)
test_diet_todo_results_never_stubbed :: proc(t: ^testing.T) {
	msgs := make([dynamic]provider.Message)
	defer diet_destroy(msgs)
	append(&msgs, provider.Message{role = .User, content = strings.clone("t")})
	append(&msgs, diet_asst("", diet_call("c1", "todo_list", `{}`)))
	append(&msgs, diet_tool("c1", "todo_list", "- [ ] one\n- [x] two"))
	append(&msgs, diet_asst("", diet_call("c2", "todo_list", `{}`)))
	append(&msgs, diet_tool("c2", "todo_list", "- [ ] one\n- [x] two"))
	append(&msgs, diet_asst("done"))

	d, st := diet_messages(msgs[:])
	defer diet_destroy(d)
	testing.expect_value(t, st.stubbed, 0)
	testing.expect_value(t, len(d), 0)
	testing.expect(t, strings.contains(msgs[4].content, "two"))
}

@(test)
test_diet_pairing_ok :: proc(t: ^testing.T) {
	msgs := make([dynamic]provider.Message)
	defer diet_destroy(msgs)
	append(&msgs, diet_asst("", diet_call("a1", "read_file", `{"path":"/p"}`)))
	append(&msgs, diet_tool("a1", "read_file", "x"))
	testing.expect(t, diet_pairing_ok(msgs[:]))

	bad := make([dynamic]provider.Message)
	defer diet_destroy(bad)
	append(&bad, diet_tool("ghost", "read_file", "x"))
	testing.expect(t, !diet_pairing_ok(bad[:]))

	// Empty id passes: tool messages without pairing metadata are allowed.
	noid := make([dynamic]provider.Message)
	defer diet_destroy(noid)
	append(&noid, provider.Message{role = .Tool, content = strings.clone("x"), name = strings.clone("run_shell")})
	testing.expect(t, diet_pairing_ok(noid[:]))
}

@(test)
test_diet_transcript_shrinks_and_pairs :: proc(t: ^testing.T) {
	os.set_env("NULLRAY_CORVUS", "0")
	defer os.unset_env("NULLRAY_CORVUS")
	msgs := make([dynamic]provider.Message)
	defer diet_destroy(msgs)
	append(&msgs, provider.Message{role = .System, content = strings.clone("sys prompt")})
	append(&msgs, provider.Message{role = .User, content = strings.clone("fix the bug in the parser")})

	fat := strings.repeat("blob ", 400, context.temp_allocator)
	steps := []struct{ id, name, args, body: string }{
		{"r1", "read_file", `{"path":"/src/parse.odin"}`, ""},
		{"s1", "run_shell", `{"command":"odin test ."}`, "PASS 1"},
		{"r2", "read_file", `{"path":"/src/parse.odin"}`, ""},
		{"w1", "web_search", `{"query":"odin parse"}`, "see https://docs.example/odin/parse"},
		{"f1", "fetch_url", `{"url":"https://docs.example/odin/parse"}`, "docs body"},
		{"s2", "run_shell", `{"command":"odin test ."}`, "PASS 2"},
		{"g1", "grep_files", `{"pattern":"parse_"}`, "m1 m2"},
		{"r3", "read_file", `{"path":"/src/util.odin"}`, "util body"},
	}
	for s in steps {
		body := s.body
		if len(body) == 0 {
			body = fat
		}
		append(&msgs, diet_asst("step", diet_call(s.id, s.name, s.args)))
		append(&msgs, diet_tool(s.id, s.name, body))
	}
	append(&msgs, diet_asst("", diet_call("r4", "read_file", `{"path":"/src/parse.odin"}`)))
	append(&msgs, diet_tool("r4", "read_file", "latest parse body"))
	append(&msgs, diet_asst("all fixed, summary here"))

	before := messages_content_chars(msgs[:])
	d, st := diet_messages(msgs[:])
	defer diet_destroy(d)

	testing.expect(t, len(d) == len(msgs))
	testing.expect(t, st.chars_after < before)
	// r1 and r2 re-reads superseded, s1 shell repeat superseded, w1 search superseded.
	testing.expect(t, strings.has_prefix(d[3].content, DIET_STUB_PREFIX))
	testing.expect(t, strings.has_prefix(d[5].content, DIET_STUB_PREFIX))
	testing.expect(t, strings.has_prefix(d[7].content, DIET_STUB_PREFIX))
	testing.expect(t, strings.has_prefix(d[9].content, DIET_STUB_PREFIX))
	testing.expect(t, diet_pairing_ok(d[:]))
	// Roles and ids preserved position for position.
	for m, i in msgs {
		testing.expect_value(t, d[i].role, m.role)
		testing.expect_value(t, d[i].tool_call_id, m.tool_call_id)
		testing.expect_value(t, d[i].name, m.name)
	}
	// Real history unchanged.
	testing.expect(t, strings.contains(msgs[3].content, "blob"))
}
