// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Tests for diff-based verify parsing, head+tail truncation, and partial apply.
*/

package subagent

import "core:fmt"
import "core:strings"
import "core:testing"

@(test)
test_verdict_token_aliases :: proc(t: ^testing.T) {
	testing.expect(t, verdict_from_token("pass") == .Pass)
	testing.expect(t, verdict_from_token("warn") == .Warn)
	testing.expect(t, verdict_from_token("needs-work") == .Warn)
	testing.expect(t, verdict_from_token("needs_work") == .Warn)
	testing.expect(t, verdict_from_token("fail") == .Block)
	testing.expect(t, verdict_from_token("block") == .Block)
	testing.expect(t, verdict_from_token("unknown-word") == .Pass)
}

@(test)
test_verify_parse_child_review_format :: proc(t: ^testing.T) {
	report := Verify_Report{
		children = make([dynamic]Verify_Child),
		findings = make([dynamic]string),
	}
	defer destroy_verify_report(&report)
	text := "CHILD|a1|fail|left debug prints and broke tests\nCHILD|a2|needs-work|missing docs\nCHILD|a3|pass|ok\nFINDING: overlapping edits in types.odin\n"
	parse_verify_text(&report, text)
	testing.expect(t, report.overall == .Block)
	testing.expect_value(t, len(report.children), 3)
	testing.expect(t, report.children[0].agent_id == "a1")
	testing.expect(t, report.children[0].verdict == .Block)
	testing.expect(t, report.children[1].verdict == .Warn)
	testing.expect(t, report.children[2].verdict == .Pass)
	testing.expect(t, strings.contains(report.children[0].reason, "broke tests"))
	testing.expect_value(t, len(report.findings), 1)
	testing.expect(t, strings.contains(report.findings[0], "overlapping edits"))
}

@(test)
test_truncate_head_tail :: proc(t: ^testing.T) {
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	for i in 0 ..< 200 {
		fmt.sbprintf(&b, "line %04d xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\n", i)
	}
	full := strings.to_string(b)
	out := truncate_head_tail(full, 2000, context.temp_allocator)
	testing.expect(t, len(out) < len(full))
	testing.expect(t, strings.has_prefix(out, "line 0000"))
	testing.expect(t, strings.contains(out, "truncated"))
	testing.expect(t, strings.contains(out, "line 0199"))
	// The middle was dropped.
	testing.expect(t, !strings.contains(out, "line 0100"))

	short := truncate_head_tail("abc", 2000, context.temp_allocator)
	testing.expect(t, short == "abc")
}

@(test)
test_apply_targets_skip_blocked :: proc(t: ^testing.T) {
	r: Roster
	roster_init(&r)
	defer roster_destroy(&r)

	h1 := Agent_Handle{
		id = strings.clone("a1"),
		isolation = .Worktree,
		worktree_branch = strings.clone("nullray/a1"),
		status = .Done,
		files_touched = make([dynamic]string),
		knowledge_keys = make([dynamic]string),
	}
	h2 := Agent_Handle{
		id = strings.clone("a2"),
		isolation = .Worktree,
		worktree_branch = strings.clone("nullray/a2"),
		status = .Done,
		files_touched = make([dynamic]string),
		knowledge_keys = make([dynamic]string),
	}
	h3 := Agent_Handle{
		id = strings.clone("a3"),
		isolation = .Shared,
		status = .Done,
		files_touched = make([dynamic]string),
		knowledge_keys = make([dynamic]string),
	}
	roster_register(&r, h1)
	roster_register(&r, h2)
	roster_register(&r, h3)
	roster_group_add(&r, "g1", "a1")
	roster_group_add(&r, "g1", "a2")
	roster_group_add(&r, "g1", "a3")

	// roster_set_verified takes ownership of the report.
	rep := Verify_Report{
		overall = .Block,
		children = make([dynamic]Verify_Child),
		findings = make([dynamic]string),
	}
	append(&rep.children, Verify_Child{
		agent_id = strings.clone("a2"),
		verdict = .Block,
		reason = strings.clone("broke the build"),
	})
	roster_set_verified(&r, "g1", rep)

	targets, found := roster_apply_targets(&r, "g1", context.temp_allocator)
	testing.expect(t, found)
	testing.expect_value(t, len(targets), 1)
	testing.expect(t, targets[0].agent_id == "a1")
	testing.expect(t, targets[0].branch == "nullray/a1")

	_, found_bad := roster_apply_targets(&r, "nope", context.temp_allocator)
	testing.expect(t, !found_bad)
}

@(test)
test_apply_report_partial :: proc(t: ^testing.T) {
	results := []Apply_Branch{
		{agent_id = "a1", branch = "nullray/a1", ok = true},
		{agent_id = "a2", branch = "nullray/a2", ok = false, err = "merge failed: CONFLICT (content)\nextra detail"},
		{agent_id = "a3", branch = "nullray/a3", ok = true},
	}
	text := apply_report_text(results, 2, context.temp_allocator)
	testing.expect(t, strings.contains(text, "merged=2 failed=1"))
	testing.expect(t, strings.contains(text, "APPLY|a1|nullray/a1|ok"))
	testing.expect(t, strings.contains(text, "APPLY|a2|nullray/a2|fail|merge failed: CONFLICT"))
	testing.expect(t, strings.contains(text, "APPLY|a3|nullray/a3|ok"))
}

@(test)
test_verify_report_text_lists_children :: proc(t: ^testing.T) {
	report := Verify_Report{
		overall = .Block,
		children = make([dynamic]Verify_Child),
		findings = make([dynamic]string),
	}
	defer destroy_verify_report(&report)
	append(&report.children, Verify_Child{
		agent_id = strings.clone("a1"),
		verdict = .Block,
		reason = strings.clone("broke tests"),
	})
	append(&report.findings, strings.clone("first finding"))
	out := verify_report_text(report, context.temp_allocator)
	testing.expect(t, strings.contains(out, "OVERALL=block"))
	testing.expect(t, strings.contains(out, "CHILD|a1|block|broke tests"))
	testing.expect(t, strings.contains(out, "FINDING: first finding"))
}
