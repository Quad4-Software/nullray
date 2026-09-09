// SPDX-License-Identifier: 0BSD
/*
App-owned subagent runtime: roster, knowledge, leases, board, limits.
*/

package subagent

import "core:strings"
import "core:sync"
import "nullray:provider"

Runtime :: struct {
	mu:              sync.Mutex,
	roster:          Roster,
	knowledge:       Knowledge_Store,
	leases:          Lease_Board,
	board:           Task_Board,
	messages:        Peer_Inbox,
	limits:          Limits,
	current_agent:   string,
	tools_reg:       rawptr,
	provider:        ^provider.Provider,
	main_model:      string,
	session_path:    string,
	session_persist: bool,
	model_locked:    bool,
	active:          bool,
	// Sum of child turn tokens not yet rolled into the parent session.
	child_total_tokens: int,
}

g_runtime: ^Runtime

runtime_set :: proc(rt: ^Runtime) {
	g_runtime = rt
}

runtime :: proc() -> ^Runtime {
	return g_runtime
}

runtime_init :: proc(rt: ^Runtime, session_id: string, tools_reg: rawptr) {
	rt^ = {}
	roster_init(&rt.roster)
	knowledge_init(&rt.knowledge, session_id)
	lease_board_init(&rt.leases)
	board_init(&rt.board)
	peer_inbox_init(&rt.messages)
	rt.limits = limits_from_env()
	rt.tools_reg = tools_reg
	rt.current_agent = strings.clone("main")
	rt.active = true
	h := Agent_Handle{
		id = strings.clone("main"),
		role = strings.clone("main"),
		status = .Idle,
		mode = strings.clone("edit"),
		files_touched = make([dynamic]string),
		knowledge_keys = make([dynamic]string),
	}
	roster_register(&rt.roster, h)
}

runtime_destroy :: proc(rt: ^Runtime) {
	if rt == nil {
		return
	}
	roster_destroy(&rt.roster)
	knowledge_destroy(&rt.knowledge)
	lease_board_destroy(&rt.leases)
	board_destroy(&rt.board)
	peer_inbox_destroy(&rt.messages)
	delete(rt.current_agent)
	delete(rt.main_model)
	delete(rt.session_path)
	policy_clear_global()
	rt^ = {}
}

runtime_set_session :: proc(rt: ^Runtime, session_path: string, persist: bool) {
	if rt == nil {
		return
	}
	delete(rt.session_path)
	rt.session_path = strings.clone(session_path)
	rt.session_persist = persist
}

runtime_add_child_tokens :: proc(rt: ^Runtime, total: int) {
	if rt == nil || total <= 0 {
		return
	}
	sync.mutex_lock(&rt.mu)
	rt.child_total_tokens += total
	sync.mutex_unlock(&rt.mu)
}

// Read and clear pending child tokens for parent session rollup.
runtime_take_child_tokens :: proc(rt: ^Runtime) -> int {
	if rt == nil {
		return 0
	}
	sync.mutex_lock(&rt.mu)
	n := rt.child_total_tokens
	rt.child_total_tokens = 0
	sync.mutex_unlock(&rt.mu)
	return n
}

runtime_set_provider :: proc(rt: ^Runtime, p: ^provider.Provider) {
	if rt == nil {
		return
	}
	rt.provider = p
}

runtime_set_current_agent :: proc(rt: ^Runtime, id: string) {
	if rt == nil {
		return
	}
	sync.mutex_lock(&rt.mu)
	delete(rt.current_agent)
	rt.current_agent = strings.clone(id)
	sync.mutex_unlock(&rt.mu)
}

runtime_current_agent :: proc(rt: ^Runtime, allocator := context.allocator) -> string {
	if rt == nil {
		return strings.clone("main", allocator)
	}
	sync.mutex_lock(&rt.mu)
	defer sync.mutex_unlock(&rt.mu)
	return strings.clone(rt.current_agent, allocator)
}

runtime_set_session_off :: proc(rt: ^Runtime, off: bool) {
	if rt == nil {
		return
	}
	rt.limits.session_off = off
}

runtime_set_cli_off :: proc(rt: ^Runtime, off: bool) {
	if rt == nil {
		return
	}
	rt.limits.cli_off = off
}

runtime_enabled :: proc(rt: ^Runtime) -> bool {
	if rt == nil {
		return false
	}
	return effective_enabled(rt.limits)
}

builtin_type_defaults :: proc(type_name: string) -> (mode: string, isolation: Isolation, role: string) {
	switch strings.to_lower(type_name, context.temp_allocator) {
	case "explore", "explore-agent":
		return "ask", .Shared, "explore"
	case "locate", "locate-agent":
		return "ask", .Shared, "explore"
	case "review", "review-agent":
		return "review", .Shared, "review"
	case "edit", "edit-agent":
		return "edit", .Worktree, "edit"
	case "shell", "shell-agent":
		return "edit", .Shared, "edit"
	case "verify":
		return "review", .Shared, "verify"
	}
	return "ask", .Shared, "explore"
}

check_write_allowed :: proc(path: string, allocator := context.allocator) -> string {
	rt := runtime()
	if rt == nil || !rt.active {
		return ""
	}
	agent_id := runtime_current_agent(rt, context.temp_allocator)
	if err := lease_check_write(&rt.leases, agent_id, path, allocator); len(err) > 0 {
		return err
	}
	_ = lease_acquire(&rt.leases, agent_id, path, "write", context.temp_allocator)
	roster_add_file(&rt.roster, agent_id, path)
	return ""
}

check_shell_allowed :: proc(command: string, allocator := context.allocator) -> string {
	rt := runtime()
	if rt == nil || !rt.active {
		return ""
	}
	agent_id := runtime_current_agent(rt, context.temp_allocator)
	if agent_id != "main" && command_is_git_stash(command) {
		return strings.clone("git stash blocked for subagents (never auto-stash)", allocator)
	}
	if command_needs_git_index_lease(command) {
		if err := lease_acquire(&rt.leases, agent_id, GIT_INDEX_LEASE, "git index", allocator); len(err) > 0 {
			return err
		}
	}
	return ""
}
