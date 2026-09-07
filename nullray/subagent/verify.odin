// SPDX-License-Identifier: 0BSD
/*
Join barrier verify-all and optional second-opinion pass.
*/

package subagent

import "core:fmt"
import "core:strings"
import "core:sync"
import "nullray:constants"
import "nullray:provider"

VERIFY_ALL_PROMPT :: `You verify work from multiple subagents. Reply with structured lines only:
OVERALL=pass|warn|block
For each child: CHILD|id|pass|warn|block|short reason
Then FINDINGS: brief cross-cutting notes or FINDINGS: none.
Be brief. Flag conflicting knowledge, overlapping edits without merge plan, escalate flags, missing tests.`

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

	body := roster_group_results_text(&rt.roster, group_id, context.temp_allocator)
	digest := knowledge_digest(&rt.knowledge, constants.MAX_KNOWLEDGE_DIGEST_CHARS, context.temp_allocator)
	user_blob := fmt.aprintf("GROUP %s\n\n%s\n\nKNOWLEDGE\n%s\n", group_id, body, digest, allocator = context.temp_allocator)
	if len(user_blob) > constants.MAX_REVIEW_DIFF_CHARS {
		user_blob = user_blob[:constants.MAX_REVIEW_DIFF_CHARS]
	}

	model, merr := policy_resolve("verify", "", prov != nil ? prov.default_model : "", rt.main_model, context.temp_allocator)
	if merr != "" {
		model = prov != nil ? prov.default_model : ""
	}

	if prov == nil || prov.chat == nil {
		// Heuristic verify without model
		report.overall = .Pass
		report.text = strings.clone("verify skipped (no provider): assume pass", allocator)
		roster_set_verified(&rt.roster, group_id, clone_verify_report(report, allocator))
		return report, ""
	}

	msgs := []provider.Message{
		{role = .System, content = VERIFY_ALL_PROMPT, cacheable = true},
		{role = .User, content = user_blob},
	}
	req := provider.Chat_Request{
		model = model,
		messages = msgs,
		stream = false,
		max_tokens = 512,
	}
	res := prov.chat(prov, req, allocator)
	if !res.ok {
		return report, res.err
	}
	text := strings.trim_space(res.content)
	delete(res.content)
	delete(res.reasoning)
	delete(res.model)
	delete(res.finish_reason)
	provider.destroy_tool_calls(res.tool_calls)

	report.text = strings.clone(text, allocator)
	parse_verify_text(&report, text, allocator)

	scan_escalate(&rt.roster, group_id, &report, allocator)

	stored := clone_verify_report(report, context.allocator)
	roster_set_verified(&rt.roster, group_id, stored)
	return report, ""
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
			case "block":
				report.overall = .Block
			case "warn":
				report.overall = .Warn
			case:
				report.overall = .Pass
			}
		} else if strings.has_prefix(low, "child|") {
			parts := strings.split(t, "|", context.temp_allocator)
			if len(parts) >= 4 {
				verdict := Verdict.Pass
				switch strings.to_lower(parts[2], context.temp_allocator) {
				case "block":
					verdict = .Block
					report.overall = .Block
				case "warn":
					verdict = .Warn
					if report.overall == .Pass {
						report.overall = .Warn
					}
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
	for f in report.findings {
		fmt.sbprintf(&b, "FINDING: %s\n", f)
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
	provider.destroy_tool_calls(res.tool_calls)
	return out, ""
}
