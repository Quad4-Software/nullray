// SPDX-License-Identifier: 0BSD
/*
Tests for subagent policy, leases, knowledge, and limits.
*/

package subagent

import "core:strings"
import "core:testing"

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
