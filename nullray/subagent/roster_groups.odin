// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Spawn groups, verify/apply, and roster text output.
*/

package subagent

import "core:fmt"
import "core:strings"
import "core:sync"
import "nullray:constants"

roster_status_text :: proc(r: ^Roster, allocator := context.allocator) -> string {
	sync.mutex_lock(&r.mu)
	defer sync.mutex_unlock(&r.mu)
	b: strings.Builder
	strings.builder_init(&b, allocator)
	if len(r.agents) == 0 {
		strings.write_string(&b, "(no agents)")
		return strings.to_string(b)
	}
	first := true
	for _, h in r.agents {
		if !first {
			strings.write_byte(&b, '\n')
		}
		first = false
		strings.write_string(&b, h.id)
		strings.write_string(&b, " ")
		strings.write_string(&b, h.role)
		strings.write_string(&b, "@")
		strings.write_string(&b, h.model)
		strings.write_string(&b, " ")
		strings.write_string(&b, status_string(h.status))
		if h.isolation == .Worktree {
			strings.write_string(&b, " wt")
		}
		if len(h.progress) > 0 {
			strings.write_string(&b, " | ")
			strings.write_string(&b, h.progress)
		}
	}
	return strings.to_string(b)
}

roster_peek_text :: proc(r: ^Roster, id: string, allocator := context.allocator) -> string {
	h, ok := roster_get(r, id, allocator)
	if !ok {
		return fmt.aprintf("unknown agent: %s", id, allocator = allocator)
	}
	b: strings.Builder
	strings.builder_init(&b, allocator)
	fmt.sbprintf(&b, "id=%s role=%s model=%s status=%s\n", h.id, h.role, h.model, status_string(h.status))
	if len(h.progress) > 0 {
		fmt.sbprintf(&b, "progress: %s\n", h.progress)
	}
	if len(h.worktree_path) > 0 {
		fmt.sbprintf(&b, "worktree: %s (%s)\n", h.worktree_path, h.worktree_branch)
	}
	if len(h.knowledge_keys) > 0 {
		strings.write_string(&b, "knowledge_keys:")
		for k in h.knowledge_keys {
			strings.write_string(&b, " ")
			strings.write_string(&b, k)
		}
		strings.write_byte(&b, '\n')
	}
	if len(h.result_summary) > 0 {
		strings.write_string(&b, "result:\n")
		strings.write_string(&b, h.result_summary)
	}
	destroy_handle_fields(&h, allocator)
	return strings.to_string(b)
}

roster_ensure_group :: proc(r: ^Roster, group_id: string) {
	sync.mutex_lock(&r.mu)
	defer sync.mutex_unlock(&r.mu)
	if _, ok := r.groups[group_id]; ok {
		return
	}
	g := Spawn_Group{
		id = strings.clone(group_id),
		agent_ids = make([dynamic]string),
	}
	r.groups[strings.clone(group_id)] = g
}

roster_group_add :: proc(r: ^Roster, group_id: string, agent_id: string) {
	roster_ensure_group(r, group_id)
	sync.mutex_lock(&r.mu)
	defer sync.mutex_unlock(&r.mu)
	if g, ok := &r.groups[group_id]; ok {
		append(&g.agent_ids, strings.clone(agent_id))
	}
}

roster_group_ids :: proc(r: ^Roster, group_id: string, allocator := context.allocator) -> [dynamic]string {
	sync.mutex_lock(&r.mu)
	defer sync.mutex_unlock(&r.mu)
	ids := make([dynamic]string, allocator)
	if g, ok := r.groups[group_id]; ok {
		for id in g.agent_ids {
			append(&ids, strings.clone(id, allocator))
		}
	}
	return ids
}

roster_group_all_done :: proc(r: ^Roster, group_id: string) -> bool {
	sync.mutex_lock(&r.mu)
	defer sync.mutex_unlock(&r.mu)
	g, ok := r.groups[group_id]
	if !ok || len(g.agent_ids) == 0 {
		return true
	}
	for id in g.agent_ids {
		h, hok := r.agents[id]
		if !hok {
			continue
		}
		if h.status == .Running || h.status == .Blocked || h.status == .Idle {
			return false
		}
	}
	return true
}

roster_group_results_text :: proc(r: ^Roster, group_id: string, allocator := context.allocator) -> string {
	sync.mutex_lock(&r.mu)
	ids: [dynamic]string
	if g, ok := r.groups[group_id]; ok {
		for id in g.agent_ids {
			append(&ids, id)
		}
	}
	sync.mutex_unlock(&r.mu)
	b: strings.Builder
	strings.builder_init(&b, allocator)
	fmt.sbprintf(&b, "group=%s done=%v\n", group_id, roster_group_all_done(r, group_id))
	for id in ids {
		h, ok := roster_get(r, id, allocator)
		if !ok {
			continue
		}
		fmt.sbprintf(&b, "--- %s [%s] ---\n", h.id, status_string(h.status))
		if len(h.result_summary) > 0 {
			sum := h.result_summary
			if len(sum) > constants.MAX_CHILD_RESULT_CHARS {
				sum = sum[:constants.MAX_CHILD_RESULT_CHARS]
			}
			strings.write_string(&b, sum)
			strings.write_byte(&b, '\n')
		}
		destroy_handle_fields(&h, allocator)
	}
	delete(ids)
	return strings.to_string(b)
}

roster_set_verified :: proc(r: ^Roster, group_id: string, report: Verify_Report) {
	roster_ensure_group(r, group_id)
	sync.mutex_lock(&r.mu)
	defer sync.mutex_unlock(&r.mu)
	if g, ok := &r.groups[group_id]; ok {
		destroy_verify_report(&g.verify)
		g.verify = report
		g.verified = true
		g.apply_ok = report.overall == .Pass || (report.overall == .Warn)
	}
}

roster_apply_allowed :: proc(r: ^Roster, group_id: string, force: bool) -> (ok: bool, reason: string) {
	sync.mutex_lock(&r.mu)
	defer sync.mutex_unlock(&r.mu)
	g, found := r.groups[group_id]
	if !found {
		return false, "unknown group"
	}
	if force {
		return true, "forced"
	}
	if !g.verified {
		return false, "verify-all required before apply"
	}
	if g.verify.overall == .Block {
		return false, "verify blocked apply"
	}
	return true, ""
}

roster_should_cancel :: proc(r: ^Roster, id: string) -> bool {
	sync.mutex_lock(&r.mu)
	defer sync.mutex_unlock(&r.mu)
	if h, ok := r.agents[id]; ok {
		return h.cancel
	}
	return false
}

roster_handle_snapshot :: proc(r: ^Roster, id: string) -> (max_steps: int, mode: string, isolation: Isolation, worktree_path: string, ok: bool) {
	sync.mutex_lock(&r.mu)
	defer sync.mutex_unlock(&r.mu)
	h, found := r.agents[id]
	if !found {
		return 0, "", .Shared, "", false
	}
	return h.max_steps, h.mode, h.isolation, h.worktree_path, true
}

Apply_Branch :: struct {
	agent_id: string,
	branch:   string,
	ok:       bool,
	err:      string,
}

/*
Ordered worktree branches eligible for apply, in group spawn order.
Children the stored verify report marked as blocked never produce a
target, so a failed-verify branch is never applied (even under --force,
which only bypasses the verified gate).
*/
roster_apply_targets :: proc(r: ^Roster, group_id: string, allocator := context.allocator) -> (targets: [dynamic]Apply_Branch, found: bool) {
	sync.mutex_lock(&r.mu)
	defer sync.mutex_unlock(&r.mu)
	g, ok := r.groups[group_id]
	if !ok {
		return nil, false
	}
	targets = make([dynamic]Apply_Branch, allocator)
	for id in g.agent_ids {
		h, hok := r.agents[id]
		if !hok || len(h.worktree_branch) == 0 {
			continue
		}
		blocked := false
		for c in g.verify.children {
			if c.agent_id == id && c.verdict == .Block {
				blocked = true
				break
			}
		}
		if blocked {
			continue
		}
		append(&targets, Apply_Branch{
			agent_id = strings.clone(id, allocator),
			branch = strings.clone(h.worktree_branch, allocator),
		})
	}
	return targets, true
}

apply_report_text :: proc(results: []Apply_Branch, merged: int, allocator := context.allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	failed := 0
	for res in results {
		if !res.ok {
			failed += 1
		}
	}
	fmt.sbprintf(&b, "merged=%d failed=%d\n", merged, failed)
	for res in results {
		if res.ok {
			fmt.sbprintf(&b, "APPLY|%s|%s|ok\n", res.agent_id, res.branch)
		} else {
			reason := res.err
			if nl := strings.index_byte(reason, '\n'); nl >= 0 {
				reason = reason[:nl]
			}
			fmt.sbprintf(&b, "APPLY|%s|%s|fail|%s\n", res.agent_id, res.branch, reason)
		}
	}
	return strings.to_string(b)
}

/*
Apply eligible worktree branches in group order. A failed merge is recorded
with its branch and the loop continues with the remaining branches, so one
conflict does not abort the whole group.
*/
roster_apply_worktrees :: proc(r: ^Roster, group_id: string, repo_root: string, allocator := context.allocator) -> (merged: int, report: string, err: string) {
	targets, found := roster_apply_targets(r, group_id, context.temp_allocator)
	if !found {
		return 0, "", strings.clone("unknown group", allocator)
	}
	results := make([dynamic]Apply_Branch, context.temp_allocator)
	for t in targets {
		mok, merr := worktree_apply_merge(repo_root, t.branch, context.temp_allocator)
		append(&results, Apply_Branch{
			agent_id = t.agent_id,
			branch = t.branch,
			ok = mok,
			err = merr,
		})
		if mok {
			merged += 1
		}
	}
	return merged, apply_report_text(results[:], merged, allocator), ""
}

roster_compact_line :: proc(r: ^Roster, allocator := context.allocator) -> string {
	sync.mutex_lock(&r.mu)
	defer sync.mutex_unlock(&r.mu)
	n := 0
	for _, h in r.agents {
		if h.id != "main" && (h.status == .Running || h.status == .Blocked) {
			n += 1
		}
	}
	if n == 0 {
		return strings.clone("", allocator)
	}
	return fmt.aprintf("%d agents", n, allocator = allocator)
}

// Living child count plus a short role sample for the TUI activity strip.
// Example: "2 live · explore@qwen · edit@sonnet" or "1 blocked · review".
roster_activity_line :: proc(r: ^Roster, max_names: int, allocator := context.allocator) -> string {
	sync.mutex_lock(&r.mu)
	defer sync.mutex_unlock(&r.mu)
	running, blocked := 0, 0
	// Collect up to max_names display labels while locked.
	cap_n := max_names
	if cap_n <= 0 {
		cap_n = 3
	}
	if cap_n > 6 {
		cap_n = 6
	}
	labels: [6]string
	n_lab := 0
	for _, h in r.agents {
		if h.id == "main" {
			continue
		}
		if h.status == .Running {
			running += 1
		} else if h.status == .Blocked {
			blocked += 1
		} else {
			continue
		}
		if n_lab < cap_n {
			role := h.role
			if len(role) == 0 {
				role = h.id
			}
			// Prefer "role" when model is empty, else "role@short-model".
			lab := role
			if len(h.model) > 0 {
				model := h.model
				// Trim provider/ prefixes and long paths for the strip.
				if slash := strings.last_index_byte(model, '/'); slash >= 0 && slash + 1 < len(model) {
					model = model[slash + 1:]
				}
				if len(model) > 16 {
					model = model[:16]
				}
				lab = fmt.tprintf("%s@%s", role, model)
			}
			if h.status == .Blocked {
				lab = fmt.tprintf("%s!", lab)
			}
			labels[n_lab] = strings.clone(lab, context.temp_allocator)
			n_lab += 1
		}
	}
	living := running + blocked
	if living == 0 {
		return strings.clone("", allocator)
	}
	b: strings.Builder
	strings.builder_init(&b, allocator)
	if blocked > 0 && running > 0 {
		fmt.sbprintf(&b, "%d live %d blocked", running, blocked)
	} else if blocked > 0 {
		fmt.sbprintf(&b, "%d blocked", blocked)
	} else {
		fmt.sbprintf(&b, "%d live", running)
	}
	if n_lab > 0 {
		strings.write_string(&b, " · ")
		for i in 0 ..< n_lab {
			if i > 0 {
				strings.write_string(&b, " · ")
			}
			strings.write_string(&b, labels[i])
		}
		extra := living - n_lab
		if extra > 0 {
			fmt.sbprintf(&b, " +%d", extra)
		}
	}
	return strings.to_string(b)
}

// Snapshot of living children for UI redraw decisions (count only).
roster_living_children :: proc(r: ^Roster) -> int {
	sync.mutex_lock(&r.mu)
	defer sync.mutex_unlock(&r.mu)
	n := 0
	for _, h in r.agents {
		if h.id != "main" && (h.status == .Running || h.status == .Blocked) {
			n += 1
		}
	}
	return n
}
