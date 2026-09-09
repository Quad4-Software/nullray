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
