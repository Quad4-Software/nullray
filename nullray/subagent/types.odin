// SPDX-License-Identifier: 0BSD
/*
Core subagent types: handles, results, verify reports, spawn specs.
*/

package subagent

import "core:time"
import "nullray:provider"

Agent_Status :: enum {
	Idle,
	Running,
	Blocked,
	Done,
	Failed,
	Cancelled,
}

Isolation :: enum {
	Shared,
	Worktree,
}

Verdict :: enum {
	Pass,
	Warn,
	Block,
}

Agent_Handle :: struct {
	id:              string,
	parent_id:       string,
	role:            string,
	model:           string,
	mode:            string,
	isolation:       Isolation,
	workspace_root:  string,
	worktree_path:   string,
	worktree_branch: string,
	status:          Agent_Status,
	progress:        string,
	group_id:        string,
	depth:           int,
	max_steps:       int,
	max_tokens:      int,
	tokens_used:     int,
	steps_used:      int,
	escalate:        bool,
	cancel:          bool,
	started_at:      time.Tick,
	result_summary:  string,
	files_touched:   [dynamic]string,
	knowledge_keys:  [dynamic]string,
}

Spawn_Spec :: struct {
	description:   string,
	prompt:        string,
	subagent_type: string,
	model:         string,
	isolation:     Isolation,
	isolation_set: bool,
	background:    bool,
	resume_id:     string,
	group_id:      string,
	max_steps:     int,
	max_tokens:    int,
	path_hints:    []string,
}

Child_Result :: struct {
	agent_id:        string,
	summary:         string,
	files_touched:   []string,
	knowledge_keys:  []string,
	worktree_path:   string,
	worktree_branch: string,
	usage:           provider.Usage,
	stop_reason:     string,
	escalate:        bool,
	ok:              bool,
	err:             string,
}

Verify_Child :: struct {
	agent_id: string,
	verdict:  Verdict,
	reason:   string,
}

Verify_Report :: struct {
	overall:   Verdict,
	children:  [dynamic]Verify_Child,
	findings:  [dynamic]string,
	forced:    bool,
	text:      string,
}

Spawn_Group :: struct {
	id:         string,
	agent_ids:  [dynamic]string,
	verified:   bool,
	verify:     Verify_Report,
	apply_ok:   bool,
}

destroy_handle_fields :: proc(h: ^Agent_Handle, allocator := context.allocator) {
	if h == nil {
		return
	}
	delete(h.id, allocator)
	delete(h.parent_id, allocator)
	delete(h.role, allocator)
	delete(h.model, allocator)
	delete(h.mode, allocator)
	delete(h.workspace_root, allocator)
	delete(h.worktree_path, allocator)
	delete(h.worktree_branch, allocator)
	delete(h.progress, allocator)
	delete(h.group_id, allocator)
	delete(h.result_summary, allocator)
	for f in h.files_touched {
		delete(f, allocator)
	}
	delete(h.files_touched)
	for k in h.knowledge_keys {
		delete(k, allocator)
	}
	delete(h.knowledge_keys)
}

destroy_child_result :: proc(r: ^Child_Result) {
	if r == nil {
		return
	}
	delete(r.agent_id)
	delete(r.summary)
	for f in r.files_touched {
		delete(f)
	}
	delete(r.files_touched)
	for k in r.knowledge_keys {
		delete(k)
	}
	delete(r.knowledge_keys)
	delete(r.worktree_path)
	delete(r.worktree_branch)
	delete(r.stop_reason)
	delete(r.err)
}

destroy_verify_report :: proc(v: ^Verify_Report) {
	if v == nil {
		return
	}
	for &c in v.children {
		delete(c.agent_id)
		delete(c.reason)
	}
	delete(v.children)
	for f in v.findings {
		delete(f)
	}
	delete(v.findings)
	delete(v.text)
}

destroy_spawn_group :: proc(g: ^Spawn_Group) {
	if g == nil {
		return
	}
	delete(g.id)
	for id in g.agent_ids {
		delete(id)
	}
	delete(g.agent_ids)
	destroy_verify_report(&g.verify)
}

status_string :: proc(s: Agent_Status) -> string {
	switch s {
	case .Idle:
		return "idle"
	case .Running:
		return "running"
	case .Blocked:
		return "blocked"
	case .Done:
		return "done"
	case .Failed:
		return "failed"
	case .Cancelled:
		return "cancelled"
	}
	return "idle"
}

isolation_string :: proc(i: Isolation) -> string {
	switch i {
	case .Shared:
		return "shared"
	case .Worktree:
		return "worktree"
	}
	return "shared"
}

isolation_from_string :: proc(s: string) -> (Isolation, bool) {
	switch s {
	case "shared", "":
		return .Shared, true
	case "worktree", "wt":
		return .Worktree, true
	}
	return .Shared, false
}

verdict_string :: proc(v: Verdict) -> string {
	switch v {
	case .Pass:
		return "pass"
	case .Warn:
		return "warn"
	case .Block:
		return "block"
	}
	return "pass"
}
