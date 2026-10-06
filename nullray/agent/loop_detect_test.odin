// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Loop detection and malformed-retry helper tests.
*/

package agent

import "core:os"
import "core:strings"
import "core:testing"
import "nullray:constants"
import "nullray:provider"
import "nullray:tools"

@(private)
mk_calls :: proc(specs: ..[2]string) -> []provider.Tool_Call {
	out := make([]provider.Tool_Call, len(specs), context.temp_allocator)
	for s, i in specs {
		out[i] = provider.Tool_Call{
			id = "x",
			name = s[0],
			arguments = s[1],
		}
	}
	return out
}

@(private)
mk_history :: proc(sigs: []u64, heads: []u64) -> Loop_History {
	h: Loop_History
	for i in 0 ..< len(sigs) {
		head := u64(0)
		if i < len(heads) {
			head = heads[i]
		}
		loop_history_push(&h, Loop_Entry{sig = sigs[i], result_head = head})
	}
	return h
}

@(test)
test_loop_sig_stable_and_distinct :: proc(t: ^testing.T) {
	a := mk_calls({"run_shell", `{"cmd":"ls"}`})
	b := mk_calls({"run_shell", `{"cmd":"ls"}`})
	c := mk_calls({"run_shell", `{"cmd":"pwd"}`})
	d := mk_calls({"read_file", `{"path":"x"}`}, {"run_shell", `{"cmd":"ls"}`})
	testing.expect(t, loop_sig_of_calls(a) == loop_sig_of_calls(b))
	testing.expect(t, loop_sig_of_calls(a) != loop_sig_of_calls(c))
	testing.expect(t, loop_sig_of_calls(a) != loop_sig_of_calls(d))
	// Argument order in the call set matters too.
	e := mk_calls({"run_shell", `{"cmd":"ls"}`}, {"read_file", `{"path":"x"}`})
	testing.expect(t, loop_sig_of_calls(d) != loop_sig_of_calls(e))
}

@(test)
test_loop_result_head_caps_at_budget :: proc(t: ^testing.T) {
	left := LOOP_RESULT_HEAD_BYTES
	h1 := loop_result_head_update(0xcbf29ce484222325, strings.repeat("a", 500, context.temp_allocator), &left)
	testing.expect_value(t, left, 0)
	left2 := LOOP_RESULT_HEAD_BYTES
	h2 := loop_result_head_update(0xcbf29ce484222325, strings.repeat("a", 200, context.temp_allocator), &left2)
	// Only the head matters; a long body hashes like its first 200 bytes.
	testing.expect(t, h1 == h2)
	// Different head bytes change the hash.
	left3 := LOOP_RESULT_HEAD_BYTES
	h3 := loop_result_head_update(0xcbf29ce484222325, strings.repeat("b", 200, context.temp_allocator), &left3)
	testing.expect(t, h1 != h3)
}

@(test)
test_loop_identical_repeat_trips_at_threshold :: proc(t: ^testing.T) {
	sig := loop_sig_of_calls(mk_calls({"run_shell", `{"cmd":"ls"}`}))
	h := mk_history([]u64{sig, sig}, []u64{7, 7})
	v, _ := loop_check(h.entries[:h.len], sig)
	testing.expect(t, v == .Identical)
	// One prior occurrence is not enough.
	h1 := mk_history([]u64{sig}, []u64{7})
	v1, _ := loop_check(h1.entries[:h1.len], sig)
	testing.expect(t, v1 == .None)
}

@(test)
test_loop_poller_never_trips :: proc(t: ^testing.T) {
	// Same command, fresh output every time: a legitimate poll loop.
	sig := loop_sig_of_calls(mk_calls({"run_shell", `{"cmd":"date"}`}))
	h := mk_history([]u64{sig, sig, sig, sig, sig}, []u64{1, 2, 3, 4, 5})
	v, _ := loop_check(h.entries[:h.len], sig)
	testing.expect(t, v == .None)
}

@(test)
test_loop_changed_result_resets_streak :: proc(t: ^testing.T) {
	sig := loop_sig_of_calls(mk_calls({"run_shell", `{"cmd":"ls"}`}))
	// Two identical, then a different result breaks the trailing run.
	h := mk_history([]u64{sig, sig, sig}, []u64{9, 9, 8})
	v, _ := loop_check(h.entries[:h.len], sig)
	testing.expect(t, v == .None)
}

@(test)
test_loop_cycle_two_trips :: proc(t: ^testing.T) {
	a := loop_sig_of_calls(mk_calls({"read_file", `{"path":"a"}`}))
	b := loop_sig_of_calls(mk_calls({"read_file", `{"path":"b"}`}))
	// A,B,A,B then A arrives: only two periods, below the 3*period bar, so a
	// legit test-read-edit rhythm stays clean.
	h2 := mk_history([]u64{a, b, a, b}, []u64{1, 2, 3, 4})
	v0, _ := loop_check(h2.entries[:h2.len], a)
	testing.expect(t, v0 == .None)
	// A,B,A,B,A then B arrives: the last three periods match.
	h := mk_history([]u64{a, b, a, b, a}, []u64{1, 2, 3, 4, 5})
	v, p := loop_check(h.entries[:h.len], b)
	testing.expect(t, v == .Cycle)
	testing.expect_value(t, p, 2)
	// Incoming sig that breaks the pattern does not trip.
	v2, _ := loop_check(h.entries[:h.len], loop_sig_of_calls(mk_calls({"read_file", `{"path":"c"}`})))
	testing.expect(t, v2 == .None)
}

@(test)
test_loop_cycle_three_trips :: proc(t: ^testing.T) {
	a := loop_sig_of_calls(mk_calls({"read_file", `{"path":"a"}`}))
	b := loop_sig_of_calls(mk_calls({"read_file", `{"path":"b"}`}))
	c := loop_sig_of_calls(mk_calls({"read_file", `{"path":"c"}`}))
	h := mk_history([]u64{a, b, c, a, b, c, a, b}, []u64{1, 2, 3, 4, 5, 6, 7, 8})
	v, p := loop_check(h.entries[:h.len], c)
	testing.expect(t, v == .Cycle)
	testing.expect_value(t, p, 3)
	// Two periods of a 3-cycle is not enough.
	h2 := mk_history([]u64{a, b, c, a, b}, []u64{1, 2, 3, 4, 5})
	v2, _ := loop_check(h2.entries[:h2.len], c)
	testing.expect(t, v2 == .None)
}

@(test)
test_loop_cycle_requires_full_repeat :: proc(t: ^testing.T) {
	a := loop_sig_of_calls(mk_calls({"read_file", `{"path":"a"}`}))
	b := loop_sig_of_calls(mk_calls({"read_file", `{"path":"b"}`}))
	// A,B,A is only 1.5 periods.
	h := mk_history([]u64{a, b}, []u64{1, 2})
	v, _ := loop_check(h.entries[:h.len], a)
	testing.expect(t, v == .None)
}

@(test)
test_loop_history_ring_evicts_oldest :: proc(t: ^testing.T) {
	h: Loop_History
	for i in 0 ..< LOOP_HISTORY_CAP + 3 {
		loop_history_push(&h, Loop_Entry{sig = u64(i), result_head = u64(i)})
	}
	testing.expect_value(t, h.len, LOOP_HISTORY_CAP)
	// Oldest three were evicted; the tail holds the newest entries.
	testing.expect(t, h.entries[LOOP_HISTORY_CAP - 1].sig == u64(LOOP_HISTORY_CAP + 2))
	testing.expect(t, h.entries[0].sig == u64(3))
}

@(test)
test_loop_marks_track_intervened_sigs :: proc(t: ^testing.T) {
	m: Loop_Marks
	testing.expect(t, !loop_marks_has(&m, 42))
	loop_marks_add(&m, 42)
	testing.expect(t, loop_marks_has(&m, 42))
	loop_marks_add(&m, 42)
	testing.expect_value(t, m.len, 1)
}

@(test)
test_loop_marks_add_cycle_marks_window :: proc(t: ^testing.T) {
	a, b := u64(11), u64(22)
	entries := []Loop_Entry{{sig = a, result_head = 1}, {sig = b, result_head = 2}}
	m: Loop_Marks
	loop_marks_add_cycle(&m, entries, a, 2)
	testing.expect(t, loop_marks_has(&m, a))
	testing.expect(t, loop_marks_has(&m, b))
}

@(test)
test_loop_marks_evict_oldest_at_cap :: proc(t: ^testing.T) {
	m: Loop_Marks
	for i in 0 ..< LOOP_MARK_CAP + 4 {
		loop_marks_add(&m, u64(1000 + i))
	}
	// Full table keeps the newest marks; the oldest four were evicted
	// instead of freezing the table and never marking again.
	testing.expect_value(t, m.len, LOOP_MARK_CAP)
	testing.expect(t, !loop_marks_has(&m, 1000))
	testing.expect(t, !loop_marks_has(&m, 1003))
	testing.expect(t, loop_marks_has(&m, u64(1000 + LOOP_MARK_CAP + 3)))
	testing.expect(t, loop_marks_has(&m, u64(1004)))
}

@(test)
test_malformed_call_class :: proc(t: ^testing.T) {
	testing.expect(t, malformed_call_class("unknown tool: foo") == .Unknown_Tool)
	testing.expect(t, malformed_call_class("unknown tool: reead_file (did you mean read_file?)") == .Unknown_Tool)
	testing.expect(t, malformed_call_class("tool not runnable: foo") == .Not_Runnable)
	testing.expect(t, malformed_call_class("bad tool args JSON: unexpected token") == .Bad_Args_Json)
	testing.expect(t, malformed_call_class("tool args must be a JSON object") == .Args_Not_Object)
	// Permission denials and normal errors never count as malformed.
	testing.expect(t, malformed_call_class("tool blocked in ask/plan/review mode (switch with /mode edit)") == .None)
	testing.expect(t, malformed_call_class("tool not in allowlist for this agent") == .None)
	testing.expect(t, malformed_call_class("permission denied") == .None)
	testing.expect(t, malformed_call_class("command exited 1") == .None)
	testing.expect(t, malformed_call_class("") == .None)
}

@(test)
test_tool_retry_budget_env :: proc(t: ^testing.T) {
	os.unset_env(constants.ENV_TOOL_RETRY)
	testing.expect_value(t, tool_retry_budget(), constants.TOOL_RETRY_DEFAULT)
	os.set_env(constants.ENV_TOOL_RETRY, "4")
	defer os.unset_env(constants.ENV_TOOL_RETRY)
	testing.expect_value(t, tool_retry_budget(), 4)
	os.set_env(constants.ENV_TOOL_RETRY, "99")
	testing.expect_value(t, tool_retry_budget(), constants.TOOL_RETRY_MAX)
	os.set_env(constants.ENV_TOOL_RETRY, "0")
	testing.expect_value(t, tool_retry_budget(), 0)
	os.set_env(constants.ENV_TOOL_RETRY, "banana")
	testing.expect_value(t, tool_retry_budget(), constants.TOOL_RETRY_DEFAULT)
}

@(test)
test_malformed_result_text_stages :: proc(t: ^testing.T) {
	retry := malformed_result_text(.Unknown_Tool, "unknown tool: foo", true, context.temp_allocator)
	testing.expect(t, strings.contains(retry, "unknown tool: foo"))
	testing.expect(t, strings.contains(retry, "retry with corrected JSON"))
	out := malformed_result_text(.Bad_Args_Json, "bad tool args JSON: x", false, context.temp_allocator)
	testing.expect(t, strings.contains(out, "budget exhausted"))
	testing.expect(t, strings.contains(out, "without further tool calls"))
}

// -- End-to-end through run_turn with a scripted provider ---------------

@(private)
Mock_Chat :: struct {
	tool_name: string,
}

@(private)
mock_chat :: proc(p: ^provider.Provider, req: provider.Chat_Request, allocator := context.allocator) -> provider.Chat_Response {
	st := cast(^Mock_Chat)p.user_data
	calls := make([]provider.Tool_Call, 1, allocator)
	calls[0] = provider.Tool_Call{
		id = strings.clone("mc1", allocator),
		name = strings.clone(st.tool_name, allocator),
		arguments = strings.clone("{}", allocator),
	}
	return provider.Chat_Response{
		ok = true,
		tool_calls = calls,
		finish_reason = strings.clone("tool_calls", allocator),
	}
}

@(private)
mock_tool_run :: proc(args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	return strings.clone("SAME_OUTPUT", allocator), ""
}

@(private)
mock_turn :: proc(t: ^testing.T, tool_name: string, reg: ^tools.Registry, max_steps: int) -> Run_Result {
	st := Mock_Chat{tool_name = tool_name}
	prov := provider.Provider{id = "mock", chat = mock_chat, user_data = &st}
	cfg := Config{
		enable_tools = true,
		stream = false,
		mode = .Edit,
		tools_registry = reg,
		max_steps = max_steps,
	}
	msgs := []provider.Message{{role = .User, content = "go"}}
	req := Run_Request{prov = &prov, messages = msgs, tools_enabled = true, model = "mock-model"}
	return run_turn(req, cfg)
}

@(private)
count_role_msgs :: proc(msgs: []provider.Message, role: provider.Role, needle: string) -> int {
	n := 0
	for m in msgs {
		if m.role == role && strings.contains(m.content, needle) {
			n += 1
		}
	}
	return n
}

@(private)
count_tool_msgs :: proc(msgs: []provider.Message, needle: string) -> int {
	return count_role_msgs(msgs, .Tool, needle)
}

@(private)
free_run_result :: proc(res: ^Run_Result) {
	if len(res.messages) > 0 {
		provider.destroy_messages(res.messages[:])
		delete(res.messages)
	} else {
		delete(res.content)
	}
	delete(res.stopped)
	delete(res.err)
}

@(test)
test_run_turn_loop_intervene_then_stop :: proc(t: ^testing.T) {
	reg: tools.Registry
	reg.tools = make([dynamic]tools.Tool, context.temp_allocator)
	tools.registry_register(&reg, tools.Tool{name = "fake_tool", kind = .Read, run = mock_tool_run})
	res := mock_turn(t, "fake_tool", &reg, 12)
	defer free_run_result(&res)
	testing.expect(t, res.ok)
	testing.expect_value(t, res.stopped, "loop")
	// The intervene nudge ran as a tool result naming the repeated tool.
	testing.expect(t, count_tool_msgs(res.messages[:], "Loop detected") >= 1)
	testing.expect(t, count_tool_msgs(res.messages[:], "fake_tool") >= 1)
}

@(test)
test_run_turn_malformed_budget :: proc(t: ^testing.T) {
	os.unset_env(constants.ENV_TOOL_RETRY)
	reg: tools.Registry
	reg.tools = make([dynamic]tools.Tool, context.temp_allocator)
	tools.registry_register(&reg, tools.Tool{name = "fake_tool", kind = .Read, run = mock_tool_run})
	res := mock_turn(t, "no_such_tool_xyz", &reg, 12)
	defer free_run_result(&res)
	testing.expect(t, res.ok)
	testing.expect(t, count_role_msgs(res.messages[:], .User, "dropped because it was malformed") >= 2)
	testing.expect(t, count_role_msgs(res.messages[:], .User, "Retry budget exhausted") >= 1)
	testing.expect_value(t, res.stopped, "loop")
}
