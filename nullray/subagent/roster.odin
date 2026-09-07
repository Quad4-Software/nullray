// SPDX-License-Identifier: 0BSD
/*
Live agent roster and spawn groups.
*/

package subagent

import "core:fmt"
import "core:strings"
import "core:sync"
import "core:time"
import "nullray:constants"

Roster :: struct {
	mu:      sync.Mutex,
	agents:  map[string]Agent_Handle,
	groups:  map[string]Spawn_Group,
	seq:     int,
}

roster_init :: proc(r: ^Roster) {
	r^ = {}
	r.agents = make(map[string]Agent_Handle)
	r.groups = make(map[string]Spawn_Group)
}

roster_destroy :: proc(r: ^Roster) {
	if r == nil {
		return
	}
	sync.mutex_lock(&r.mu)
	for k, &h in r.agents {
		destroy_handle_fields(&h)
		delete(k)
	}
	delete(r.agents)
	for k, &g in r.groups {
		destroy_spawn_group(&g)
		delete(k)
	}
	delete(r.groups)
	sync.mutex_unlock(&r.mu)
	r^ = {}
}

roster_next_id :: proc(r: ^Roster, allocator := context.allocator) -> string {
	sync.mutex_lock(&r.mu)
	r.seq += 1
	n := r.seq
	sync.mutex_unlock(&r.mu)
	return fmt.aprintf("a%x", n, allocator = allocator)
}

roster_agent_depth :: proc(r: ^Roster, id: string) -> (depth: int, ok: bool) {
	sync.mutex_lock(&r.mu)
	defer sync.mutex_unlock(&r.mu)
	h, found := r.agents[id]
	if !found {
		return 0, false
	}
	return h.depth, true
}

roster_register :: proc(r: ^Roster, h: Agent_Handle) {
	sync.mutex_lock(&r.mu)
	defer sync.mutex_unlock(&r.mu)
	if old, ok := r.agents[h.id]; ok {
		destroy_handle_fields(&old)
		delete_key(&r.agents, h.id)
	}
	key := strings.clone(h.id)
	r.agents[key] = h
}

roster_get :: proc(r: ^Roster, id: string, allocator := context.allocator) -> (Agent_Handle, bool) {
	sync.mutex_lock(&r.mu)
	defer sync.mutex_unlock(&r.mu)
	h, ok := r.agents[id]
	if !ok {
		return {}, false
	}
	out := Agent_Handle{}
	out.id = strings.clone(h.id, allocator)
	out.parent_id = strings.clone(h.parent_id, allocator)
	out.role = strings.clone(h.role, allocator)
	out.model = strings.clone(h.model, allocator)
	out.mode = strings.clone(h.mode, allocator)
	out.isolation = h.isolation
	out.workspace_root = strings.clone(h.workspace_root, allocator)
	out.worktree_path = strings.clone(h.worktree_path, allocator)
	out.worktree_branch = strings.clone(h.worktree_branch, allocator)
	out.status = h.status
	out.progress = strings.clone(h.progress, allocator)
	out.group_id = strings.clone(h.group_id, allocator)
	out.depth = h.depth
	out.max_steps = h.max_steps
	out.max_tokens = h.max_tokens
	out.tokens_used = h.tokens_used
	out.steps_used = h.steps_used
	out.escalate = h.escalate
	out.cancel = h.cancel
	out.started_at = h.started_at
	out.result_summary = strings.clone(h.result_summary, allocator)
	out.files_touched = make([dynamic]string, allocator)
	for f in h.files_touched {
		append(&out.files_touched, strings.clone(f, allocator))
	}
	out.knowledge_keys = make([dynamic]string, allocator)
	for k in h.knowledge_keys {
		append(&out.knowledge_keys, strings.clone(k, allocator))
	}
	return out, true
}

roster_set_status :: proc(r: ^Roster, id: string, status: Agent_Status) {
	sync.mutex_lock(&r.mu)
	defer sync.mutex_unlock(&r.mu)
	if h, ok := &r.agents[id]; ok {
		h.status = status
	}
}

roster_set_progress :: proc(r: ^Roster, id: string, note: string) {
	sync.mutex_lock(&r.mu)
	defer sync.mutex_unlock(&r.mu)
	if h, ok := &r.agents[id]; ok {
		delete(h.progress)
		trimmed := strings.trim_space(note)
		if len(trimmed) > 200 {
			trimmed = trimmed[:200]
		}
		h.progress = strings.clone(trimmed)
	}
}

roster_request_cancel :: proc(r: ^Roster, id: string) {
	sync.mutex_lock(&r.mu)
	defer sync.mutex_unlock(&r.mu)
	if h, ok := &r.agents[id]; ok {
		h.cancel = true
	}
}

roster_cancel_children_of :: proc(r: ^Roster, parent_id: string) {
	sync.mutex_lock(&r.mu)
	defer sync.mutex_unlock(&r.mu)
	for _, &h in r.agents {
		if h.parent_id == parent_id && (h.status == .Running || h.status == .Blocked || h.status == .Idle) {
			h.cancel = true
		}
	}
}

roster_living_count :: proc(r: ^Roster) -> int {
	sync.mutex_lock(&r.mu)
	defer sync.mutex_unlock(&r.mu)
	n := 0
	for _, h in r.agents {
		if h.status == .Running || h.status == .Blocked || h.status == .Idle {
			if h.id != "main" {
				n += 1
			}
		}
	}
	return n
}

roster_finish :: proc(r: ^Roster, id: string, summary: string, escalate: bool, failed: bool) {
	sync.mutex_lock(&r.mu)
	defer sync.mutex_unlock(&r.mu)
	if h, ok := &r.agents[id]; ok {
		delete(h.result_summary)
		h.result_summary = strings.clone(summary)
		h.escalate = escalate
		h.status = failed ? .Failed : .Done
	}
}

roster_add_file :: proc(r: ^Roster, id: string, path: string) {
	sync.mutex_lock(&r.mu)
	defer sync.mutex_unlock(&r.mu)
	if h, ok := &r.agents[id]; ok {
		for f in h.files_touched {
			if f == path {
				return
			}
		}
		append(&h.files_touched, strings.clone(path))
	}
}

roster_add_knowledge_key :: proc(r: ^Roster, id: string, key: string) {
	sync.mutex_lock(&r.mu)
	defer sync.mutex_unlock(&r.mu)
	if h, ok := &r.agents[id]; ok {
		for k in h.knowledge_keys {
			if k == key {
				return
			}
		}
		append(&h.knowledge_keys, strings.clone(key))
	}
}

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

roster_apply_worktrees :: proc(r: ^Roster, group_id: string, repo_root: string, allocator := context.allocator) -> (merged: int, err: string) {
	sync.mutex_lock(&r.mu)
	defer sync.mutex_unlock(&r.mu)
	g, found := r.groups[group_id]
	if !found {
		return 0, strings.clone("unknown group", allocator)
	}
	for id in g.agent_ids {
		h, hok := r.agents[id]
		if !hok || len(h.worktree_branch) == 0 {
			continue
		}
		mok, merr := worktree_apply_merge(repo_root, h.worktree_branch, allocator)
		if !mok {
			return merged, merr
		}
		merged += 1
	}
	return merged, ""
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
