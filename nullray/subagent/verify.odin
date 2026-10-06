// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Join barrier verify-all and optional second-opinion pass.

verify_all is a Devin-Review-style adversarial pass: worktree children get
their actual diff vs the merge base reviewed, shared-isolation children fall
back to summary review (plus small file heads when they list touched files).
At most VERIFY_REVIEW_MAX_CALLS chat calls run; children past the call budget
are appended to the last call as summary-only sections.
*/

package subagent

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:sync"
import "nullray:constants"
import "nullray:provider"
import "nullray:sandbox"

VERIFY_REVIEW_MAX_CALLS :: 3
VERIFY_FILE_HEADS_MAX :: 5
VERIFY_FILE_HEAD_BYTES :: 2_048

VERIFY_REVIEW_PROMPT :: `You are an adversarial reviewer of subagent work.
Each CHILD section gives the task, the agent's own summary, and for worktree-isolated agents the actual diff vs the merge base.
Judge the diff, not the summary. Flag incomplete edits, failing or missing tests, secrets, dead code, unrelated changes, and overlapping edits.
Reply with structured lines only:
CHILD|id|pass|fail|needs-work|short reason
One CHILD line per child id shown. pass = safe to merge. fail = do not merge. needs-work = mergeable only after fixes.
Then FINDING: lines for cross-cutting issues, or FINDINGS: none.
Be brief.`

verify_all :: proc(
	rt: ^Runtime,
	group_id: string,
	prov: ^provider.Provider,
	allocator := context.allocator,
) -> (report: Verify_Report, err: string) {
	report = Verify_Report{
		children = make([dynamic]Verify_Child, allocator),
		findings = make([dynamic]string, allocator),
	}
	if rt == nil {
		return report, strings.clone("no runtime", allocator)
	}
	if !roster_group_all_done(&rt.roster, group_id) {
		return report, strings.clone("group still running (agents_wait first)", allocator)
	}

	if prov == nil || prov.chat == nil {
		// Heuristic verify without model
		report.overall = .Pass
		report.text = strings.clone("verify skipped (no provider): assume pass", allocator)
		roster_set_verified(&rt.roster, group_id, clone_verify_report(report, allocator))
		return report, ""
	}

	// Snapshot children. Worktree children first so the limited diff-review
	// calls go to real diffs; summary-only review covers the rest.
	ids := roster_group_ids(&rt.roster, group_id, context.temp_allocator)
	handles := make([dynamic]Agent_Handle, context.temp_allocator)
	for id in ids {
		if h, ok := roster_get(&rt.roster, id, context.temp_allocator); ok {
			append(&handles, h)
		}
	}
	ordered := make([dynamic]Agent_Handle, context.temp_allocator)
	for h in handles {
		if h.isolation == .Worktree && len(h.worktree_branch) > 0 {
			append(&ordered, h)
		}
	}
	for h in handles {
		if !(h.isolation == .Worktree && len(h.worktree_branch) > 0) {
			append(&ordered, h)
		}
	}

	n := len(ordered)
	if n == 0 {
		report.overall = .Pass
		report.text = strings.clone("no children in group", allocator)
		roster_set_verified(&rt.roster, group_id, clone_verify_report(report, allocator))
		return report, ""
	}

	calls := n < VERIFY_REVIEW_MAX_CALLS ? n : VERIFY_REVIEW_MAX_CALLS
	repo_root := workspace_dir(context.temp_allocator)
	digest := knowledge_digest(&rt.knowledge, constants.MAX_KNOWLEDGE_DIGEST_CHARS, context.temp_allocator)

	// One user blob per call; the first `calls` children get detailed
	// sections, the rest are summarized into the last call.
	bodies := make([]strings.Builder, calls, context.temp_allocator)
	for &b in bodies {
		strings.builder_init(&b, context.temp_allocator)
	}
	summary_note_done := false
	for h, i in ordered {
		ci := i
		detailed := true
		if ci >= calls {
			ci = calls - 1
			detailed = false
		}
		if !detailed && !summary_note_done {
			strings.write_string(&bodies[ci], "\nSUMMARY-ONLY children (no diff reviewed; judge from summary):\n")
			summary_note_done = true
		}
		verify_child_section(&bodies[ci], h, repo_root, detailed)
	}

	model, merr := policy_resolve("verify", "", prov.default_model, rt.main_model, context.temp_allocator)
	if merr != "" {
		model = prov.default_model
	}

	raw: strings.Builder
	strings.builder_init(&raw, context.temp_allocator)
	last_err := ""
	any_ok := false
	for ci in 0 ..< calls {
		user_blob := fmt.aprintf(
			"GROUP %s\n\nKNOWLEDGE\n%s\n\n%s",
			group_id,
			digest,
			strings.to_string(bodies[ci]),
			allocator = context.temp_allocator,
		)
		msgs := []provider.Message{
			{role = .System, content = VERIFY_REVIEW_PROMPT, cacheable = true},
			{role = .User, content = user_blob},
		}
		req := provider.Chat_Request{
			model = model,
			messages = msgs,
			stream = false,
			max_tokens = 512,
		}
		res := prov.chat(prov, req, context.temp_allocator)
		if !res.ok {
			last_err = res.err
			append(&report.findings, fmt.aprintf("verify call %d failed: %s", ci + 1, res.err, allocator = allocator))
			continue
		}
		any_ok = true
		text := strings.trim_space(res.content)
		if len(text) > 0 {
			strings.write_string(&raw, text)
			strings.write_byte(&raw, '\n')
		}
		parse_verify_text(&report, text, allocator)
		delete(res.content)
		delete(res.reasoning)
		delete(res.model)
		delete(res.finish_reason)
		provider.destroy_tool_calls_owned(res.tool_calls)
	}
	if !any_ok && len(last_err) > 0 {
		return report, strings.clone(last_err, allocator)
	}

	// Every child gets a verdict row; uncovered ones get a warn placeholder.
	for h in ordered {
		covered := false
		for c in report.children {
			if c.agent_id == h.id {
				covered = true
				break
			}
		}
		if covered {
			continue
		}
		append(&report.children, Verify_Child{
			agent_id = strings.clone(h.id, allocator),
			verdict = .Warn,
			reason = strings.clone("no verdict in reviewer output", allocator),
		})
		if report.overall == .Pass {
			report.overall = .Warn
		}
	}

	full := strings.trim_space(strings.to_string(raw))
	report.text = truncate_head_tail(full, constants.MAX_VERIFY_OUTPUT_BYTES, allocator)

	scan_escalate(&rt.roster, group_id, &report, allocator)

	stored := clone_verify_report(report, context.allocator)
	roster_set_verified(&rt.roster, group_id, stored)
	return report, ""
}
verdict_from_token :: proc(tok: string) -> Verdict {
	switch strings.to_lower(strings.trim_space(tok), context.temp_allocator) {
	case "block", "fail", "failed", "error":
		return .Block
	case "warn", "needs-work", "needs_work", "needswork":
		return .Warn
	}
	return .Pass
}

parse_verify_text :: proc(report: ^Verify_Report, text: string, allocator := context.allocator) {
	report.overall = .Pass
	lines := strings.split_lines(text, context.temp_allocator)
	for line in lines {
		t := strings.trim_space(line)
		low := strings.to_lower(t, context.temp_allocator)
		if strings.has_prefix(low, "overall=") {
			v := low[8:]
			switch v {
			case "block", "fail":
				report.overall = .Block
			case "warn", "needs-work":
				report.overall = .Warn
			case:
				report.overall = .Pass
			}
		} else if strings.has_prefix(low, "child|") {
			parts := strings.split(t, "|", context.temp_allocator)
			if len(parts) >= 4 {
				verdict := verdict_from_token(parts[2])
				if verdict == .Block {
					report.overall = .Block
				} else if verdict == .Warn && report.overall == .Pass {
					report.overall = .Warn
				}
				reason := ""
				if len(parts) >= 5 {
					reason = strings.join(parts[3:], "|", context.temp_allocator)
				} else {
					reason = parts[3]
				}
				append(&report.children, Verify_Child{
					agent_id = strings.clone(parts[1], allocator),
					verdict = verdict,
					reason = strings.clone(reason, allocator),
				})
			}
		} else if strings.has_prefix(low, "findings:") {
			rest := strings.trim_space(t[9:])
			if rest != "none" && len(rest) > 0 {
				append(&report.findings, strings.clone(rest, allocator))
			}
		} else if strings.has_prefix(low, "finding:") {
			rest := strings.trim_space(t[8:])
			if rest != "none" && len(rest) > 0 {
				append(&report.findings, strings.clone(rest, allocator))
			}
		}
	}
}

scan_escalate :: proc(r: ^Roster, group_id: string, report: ^Verify_Report, allocator := context.allocator) {
	sync.mutex_lock(&r.mu)
	defer sync.mutex_unlock(&r.mu)
	g, ok := r.groups[group_id]
	if !ok {
		return
	}
	for id in g.agent_ids {
		if h, hok := r.agents[id]; hok && h.escalate {
			if report.overall == .Pass {
				report.overall = .Warn
			}
			append(&report.findings, fmt.aprintf("escalate from %s", id, allocator = allocator))
		}
	}
}

clone_verify_report :: proc(src: Verify_Report, allocator := context.allocator) -> Verify_Report {
	out := Verify_Report{
		overall = src.overall,
		forced = src.forced,
		children = make([dynamic]Verify_Child, allocator),
		findings = make([dynamic]string, allocator),
		text = strings.clone(src.text, allocator),
	}
	for c in src.children {
		append(&out.children, Verify_Child{
			agent_id = strings.clone(c.agent_id, allocator),
			verdict = c.verdict,
			reason = strings.clone(c.reason, allocator),
		})
	}
	for f in src.findings {
		append(&out.findings, strings.clone(f, allocator))
	}
	return out
}

verify_report_text :: proc(report: Verify_Report, allocator := context.allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	fmt.sbprintf(&b, "OVERALL=%s\n", verdict_string(report.overall))
	for c in report.children {
		fmt.sbprintf(&b, "CHILD|%s|%s|%s\n", c.agent_id, verdict_string(c.verdict), c.reason)
	}
	shown := 0
	for f in report.findings {
		if shown >= constants.MAX_VERIFY_FINDINGS {
			fmt.sbprintf(&b, "FINDING: ... (%d more)\n", len(report.findings) - shown)
			break
		}
		fmt.sbprintf(&b, "FINDING: %s\n", f)
		shown += 1
	}
	if len(report.text) > 0 {
		strings.write_string(&b, report.text)
	}
	return strings.to_string(b)
}

/*
Second-opinion adversarial verify when teams mode is on.
*/
verify_second_opinion :: proc(
	rt: ^Runtime,
	group_id: string,
	prov: ^provider.Provider,
	first: Verify_Report,
	allocator := context.allocator,
) -> (text: string, err: string) {
	if !teams_enabled_from_env() {
		return "", strings.clone("second opinion requires NULLRAY_SUBAGENT_TEAMS=1", allocator)
	}
	if prov == nil || prov.chat == nil {
		return "", strings.clone("no provider", allocator)
	}
	prompt := fmt.tprintf(
		"Re-check this verify report for group %s. Reply OVERALL=pass|warn|block and brief disagreement notes.\n\n%s",
		group_id,
		first.text,
	)
	model, _ := policy_resolve("review", "", prov.default_model, rt.main_model, context.temp_allocator)
	msgs := []provider.Message{
		{role = .System, content = "You are an adversarial reviewer. Be brief.", cacheable = true},
		{role = .User, content = prompt},
	}
	req := provider.Chat_Request{model = model, messages = msgs, stream = false, max_tokens = 256}
	res := prov.chat(prov, req, allocator)
	if !res.ok {
		return "", res.err
	}
	out := strings.clone(strings.trim_space(res.content), allocator)
	delete(res.content)
	delete(res.reasoning)
	delete(res.model)
	delete(res.finish_reason)
	provider.destroy_tool_calls_owned(res.tool_calls)
	return out, ""
}
