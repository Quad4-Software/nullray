// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Tests for subagent policy, leases, knowledge, and limits.
*/

package subagent

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"
import "core:time"

@(test)
test_limits_disable :: proc(t: ^testing.T) {
	lim := Limits{enabled = true, max = 3}
	testing.expect(t, effective_enabled(lim))
	lim.max = 0
	testing.expect(t, !effective_enabled(lim))
	lim.max = 3
	lim.session_off = true
	testing.expect(t, !effective_enabled(lim))
}

@(test)
test_policy_approve_empty_means_any :: proc(t: ^testing.T) {
	policy_clear_global()
	policy_ensure_loaded()
	testing.expect(t, policy_is_approved("any-model-xyz"))
}

@(test)
test_knowledge_put_get :: proc(t: ^testing.T) {
	k: Knowledge_Store
	knowledge_init(&k, "test-session")
	defer knowledge_destroy(&k)
	err := knowledge_put(&k, "fact1", "hello", "a1", {})
	testing.expect(t, err == "")
	text, gerr := knowledge_get(&k, "fact1")
	testing.expect(t, gerr == "")
	testing.expect(t, len(text) > 0)
	delete(text)
}

@(test)
test_knowledge_rejects_secrets :: proc(t: ^testing.T) {
	k: Knowledge_Store
	knowledge_init(&k, "test-session-2")
	defer knowledge_destroy(&k)
	err := knowledge_put(&k, "bad", "api_key=secret", "a1", {})
	testing.expect(t, len(err) > 0)
	delete(err)
}

@(test)
test_lease_conflict :: proc(t: ^testing.T) {
	b: Lease_Board
	lease_board_init(&b)
	defer lease_board_destroy(&b)
	err := lease_acquire(&b, "a1", "/tmp/foo.odin", "edit")
	testing.expect(t, err == "")
	err2 := lease_acquire(&b, "a2", "/tmp/foo.odin", "edit")
	testing.expect(t, len(err2) > 0)
	delete(err2)
	lease_release_agent(&b, "a1")
	err3 := lease_acquire(&b, "a2", "/tmp/foo.odin", "edit")
	testing.expect(t, err3 == "")
	lease_release_agent(&b, "a2")
}

@(test)
test_roster_status :: proc(t: ^testing.T) {
	r: Roster
	roster_init(&r)
	defer roster_destroy(&r)
	h := Agent_Handle{
		id = strings.clone("a1"),
		role = strings.clone("explore"),
		model = strings.clone("fast"),
		status = .Running,
		progress = strings.clone("searching"),
		files_touched = make([dynamic]string),
		knowledge_keys = make([dynamic]string),
	}
	roster_register(&r, h)
	text := roster_status_text(&r)
	testing.expect(t, strings.contains(text, "a1"))
	delete(text)
}

@(test)
test_verify_parse :: proc(t: ^testing.T) {
	report := Verify_Report{
		children = make([dynamic]Verify_Child),
		findings = make([dynamic]string),
	}
	defer destroy_verify_report(&report)
	parse_verify_text(&report, "OVERALL=warn\nCHILD|a1|pass|ok\nFINDINGS: overlap\n")
	testing.expect(t, report.overall == .Warn)
	testing.expect(t, len(report.children) == 1)
}

@(test)
test_roster_depth_no_alloc_crash :: proc(t: ^testing.T) {
	r: Roster
	roster_init(&r)
	defer roster_destroy(&r)
	h := Agent_Handle{
		id = strings.clone("main"),
		role = strings.clone("main"),
		mode = strings.clone("edit"),
		status = .Idle,
		depth = 0,
		files_touched = make([dynamic]string),
		knowledge_keys = make([dynamic]string),
	}
	roster_register(&r, h)
	d, ok := roster_agent_depth(&r, "main")
	testing.expect(t, ok)
	testing.expect(t, d == 0)
}

@(test)
test_locate_type_defaults :: proc(t: ^testing.T) {
	mode, isol, role := builtin_type_defaults("locate")
	testing.expect(t, mode == "ask")
	testing.expect(t, isol == .Shared)
	testing.expect(t, role == "explore")
}

@(test)
test_architect_type_defaults :: proc(t: ^testing.T) {
	mode, isol, role := builtin_type_defaults("architect")
	testing.expect(t, mode == "ask")
	testing.expect(t, isol == .Shared)
	testing.expect(t, role == "explore")
}

@(test)
test_architect_preamble_mentions_contract :: proc(t: ^testing.T) {
	rt: Runtime
	text := build_architect_preamble(&rt, "a1", "main", context.allocator)
	defer delete(text)
	testing.expect(t, strings.contains(text, "## Steps"))
	testing.expect(t, strings.contains(text, "list_scaffolds"))
	testing.expect(t, !strings.contains(text, "knowledge_put"))
}

@(test)
test_locate_preamble_mentions_cites :: proc(t: ^testing.T) {
	rt: Runtime
	text := build_locate_preamble(&rt, "a1", "main", context.allocator)
	defer delete(text)
	testing.expect(t, strings.contains(text, "CITES"))
	testing.expect(t, strings.contains(text, "repo_map"))
	testing.expect(t, !strings.contains(text, "knowledge_put"))
}

@(test)
test_runtime_child_token_rollup :: proc(t: ^testing.T) {
	rt: Runtime
	runtime_add_child_tokens(&rt, 0)
	testing.expect_value(t, runtime_take_child_tokens(&rt), 0)
	runtime_add_child_tokens(&rt, 120)
	runtime_add_child_tokens(&rt, 30)
	testing.expect_value(t, runtime_take_child_tokens(&rt), 150)
	testing.expect_value(t, runtime_take_child_tokens(&rt), 0)
}

// In-memory board, no persistence dir.
board_test_fresh :: proc(b: ^Task_Board) {
	b^ = {}
	b.items = make([dynamic]Board_Item)
}

// Board rooted at a clean temp dir so save/load stay off the workspace.
// Returned dir is temp-allocated; b.dir is an owned clone.
board_test_dir :: proc(b: ^Task_Board, tag: string) -> string {
	base, _ := os.temp_dir(context.temp_allocator)
	dir, _ := filepath.join({base, fmt.tprintf("nullray_board_%s", tag)}, context.temp_allocator)
	_ = os.remove_all(dir)
	_ = os.make_directory_all(dir)
	b^ = {}
	b.items = make([dynamic]Board_Item)
	b.dir = strings.clone(dir)
	return dir
}

@(test)
test_board_claim_blocked_by_deps :: proc(t: ^testing.T) {
	b: Task_Board
	board_test_fresh(&b)
	defer board_destroy(&b)
	a, _ := board_add(&b, "first")
	defer delete(a)
	c, _ := board_add(&b, "second", []string{a})
	defer delete(c)
	err := board_claim(&b, c, "agent-1")
	testing.expect(t, len(err) > 0)
	testing.expect(t, strings.contains(err, a))
	delete(err)
	lst := board_list_text(&b)
	testing.expect(t, strings.contains(lst, "blocked-by="))
	testing.expect(t, strings.contains(lst, a))
	delete(lst)
	derr := board_done(&b, a, "agent-1", "shipped")
	testing.expect(t, derr == "")
	cerr := board_claim(&b, c, "agent-1")
	testing.expect(t, cerr == "")
}

@(test)
test_board_claim_unknown_dep_blocks :: proc(t: ^testing.T) {
	b: Task_Board
	board_test_fresh(&b)
	defer board_destroy(&b)
	x, _ := board_add(&b, "ghost dep", []string{"t999"})
	defer delete(x)
	err := board_claim(&b, x, "agent-1")
	testing.expect(t, len(err) > 0)
	testing.expect(t, strings.contains(err, "t999"))
	delete(err)
}

@(test)
test_board_result_persist_roundtrip :: proc(t: ^testing.T) {
	if knowledge_ephemeral() {
		return
	}
	b: Task_Board
	dir := board_test_dir(&b, "roundtrip")
	defer board_destroy(&b)
	a, _ := board_add(&b, "alpha", nil, "")
	defer delete(a)
	c, _ := board_add(&b, "beta", []string{a}, "g1")
	defer delete(c)
	derr := board_done(&b, a, "a1", "alpha shipped")
	testing.expect(t, derr == "")

	b2: Task_Board
	b2.items = make([dynamic]Board_Item)
	b2.dir = strings.clone(dir)
	defer board_destroy(&b2)
	board_load(&b2)
	testing.expect_value(t, len(b2.items), 2)
	testing.expect_value(t, b2.seq, 2)
	seen_a, seen_c := false, false
	for it in b2.items {
		if it.id == a {
			seen_a = true
			testing.expect(t, it.status == .Done)
			testing.expect(t, it.result == "alpha shipped")
		}
		if it.id == c {
			seen_c = true
			testing.expect(t, it.group == "g1")
			testing.expect_value(t, len(it.blocked_on), 1)
			testing.expect(t, it.blocked_on[0] == a)
		}
	}
	testing.expect(t, seen_a)
	testing.expect(t, seen_c)
}

@(test)
test_board_load_legacy_line :: proc(t: ^testing.T) {
	b: Task_Board
	dir := board_test_dir(&b, "legacy")
	defer board_destroy(&b)
	path, _ := filepath.join({dir, "items.jsonl"}, context.temp_allocator)
	// Legacy line lacks group/blocked_on/result keys.
	legacy := `{"id":"t7","title":"old item","assignee":"a9","status":"claimed","updated":1}` + "\n"
	_ = os.write_entire_file(path, transmute([]byte)legacy)
	board_load(&b)
	testing.expect_value(t, len(b.items), 1)
	it := b.items[0]
	testing.expect(t, it.id == "t7")
	testing.expect(t, it.status == .Claimed)
	testing.expect(t, it.assignee == "a9")
	testing.expect(t, len(it.group) == 0)
	testing.expect(t, len(it.result) == 0)
	testing.expect_value(t, len(it.blocked_on), 0)
	testing.expect_value(t, b.seq, 7)
}

@(test)
test_board_group_filter :: proc(t: ^testing.T) {
	b: Task_Board
	board_test_fresh(&b)
	defer board_destroy(&b)
	ga, _ := board_add(&b, "g1 task", nil, "g1")
	defer delete(ga)
	gb, _ := board_add(&b, "g2 task", nil, "g2")
	defer delete(gb)
	plain, _ := board_add(&b, "all task")
	defer delete(plain)

	lst := board_list_text(&b, "g1")
	testing.expect(t, strings.contains(lst, "g1 task"))
	testing.expect(t, strings.contains(lst, "all task"))
	testing.expect(t, !strings.contains(lst, "g2 task"))
	delete(lst)

	all := board_list_text(&b)
	testing.expect(t, strings.contains(all, "g1 task"))
	testing.expect(t, strings.contains(all, "g2 task"))
	testing.expect(t, strings.contains(all, "all task"))
	delete(all)
}

@(test)
test_session_bind_tls_roundtrip :: proc(t: ^testing.T) {
	_, _, ok_before := session_bind()
	testing.expect(t, !ok_before)
	prev := session_bind_set("/tmp/sess-a.jsonl", true)
	defer session_bind_clear(prev)
	path, persist, ok := session_bind()
	testing.expect(t, ok)
	testing.expect(t, path == "/tmp/sess-a.jsonl")
	testing.expect(t, persist)
	session_bind_clear(prev)
	_, _, ok_after := session_bind()
	testing.expect(t, !ok_after)
}

// Regression: a detached grandchild holding the pipe write end must not
// wedge the post-exit drain, and the real exit code must surface.
@(test)
test_run_cmd_detached_grandchild :: proc(t: ^testing.T) {
	when ODIN_OS == .Windows {
		return
	}
	start := time.now()
	out, err := run_cmd([]string{"/bin/sh", "-c", "sleep 15 & exit 7"}, ".", context.allocator)
	defer delete(out)
	defer delete(err)
	testing.expectf(t, strings.contains(err, "exit 7"), "err=%q", err)
	testing.expectf(t, time.since(start) < 10 * time.Second, "detached grandchild wedged the drain")
}
