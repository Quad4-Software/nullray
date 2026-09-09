// SPDX-License-Identifier: 0BSD
/*
Read-only speculative tool pool: submit, join by hash, discard on miss/cancel.
*/

package tools

import "core:mem"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"
import "nullray:constants"

Speculate_State :: enum {
	Queued,
	Running,
	Ready,
	Failed,
	Cancelled,
}

Speculate_Entry :: struct {
	id:          string,
	name:        string,
	args:        string,
	args_hash:   u64,
	state:       Speculate_State,
	result:      string,
	err:         string,
	pre_ran:     bool,
	blocked_pre: bool,
	duration_ms: i64,
	th:          ^thread.Thread,
	mu:          sync.Mutex,
}

Speculate_Pool :: struct {
	mu:           sync.Mutex,
	entries:      [dynamic]^Speculate_Entry,
	active:       int,
	max_parallel: int,
	admit:        bool,
	reg:          ^Registry,
	mode:         string,
	tool_allow:   []string,
	allocator:    mem.Allocator,
}

Speculate_Job :: struct {
	pool:  ^Speculate_Pool,
	entry: ^Speculate_Entry,
}

speculate_enabled_from_env :: proc() -> bool {
	if v, ok := os.lookup_env(constants.ENV_SPECULATE, context.temp_allocator); ok {
		switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
		case "0", "false", "no", "off", "disable":
			return false
		case "1", "true", "yes", "on":
			return true
		}
	}
	return true
}

speculate_parallel_from_env :: proc() -> int {
	n := constants.DEFAULT_SPECULATE_PARALLEL
	if v, ok := os.lookup_env(constants.ENV_SPECULATE_PARALLEL, context.temp_allocator); ok {
		parsed, pok := strconv.parse_int(v)
		if pok && parsed >= 1 {
			n = parsed
		}
	}
	if n > 8 {
		n = 8
	}
	return n
}

speculate_allowlisted :: proc(name: string) -> bool {
	switch name {
	case "read_file", "list_dir", "repo_map", "grep_files", "glob_files",
		"read_man", "apropos", "read_tldr", "read_info", "read_help", "lang_doc",
		"list_skills", "load_skill",
		"memory_get", "memory_list", "memory_search",
		"rag_status", "rag_query",
		"read_artifact", "grep_artifact",
		"vcs_status", "vcs_diff", "vcs_log", "vcs_pr_view",
		"audit_structure", "audit_actions", "audit_dockerfile",
		"audit_compose", "audit_owasp", "audit_deps":
		return true
	}
	return false
}

speculate_pool_init :: proc(
	pool: ^Speculate_Pool,
	reg: ^Registry,
	mode: string,
	max_parallel: int,
	allocator := context.allocator,
	tool_allow: []string = nil,
) {
	pool^ = {}
	pool.entries = make([dynamic]^Speculate_Entry, allocator)
	pool.max_parallel = max_parallel
	if pool.max_parallel < 1 {
		pool.max_parallel = constants.DEFAULT_SPECULATE_PARALLEL
	}
	pool.admit = true
	pool.reg = reg
	pool.mode = strings.clone(mode, allocator)
	pool.tool_allow = tool_allow
	pool.allocator = allocator
}

speculate_entry_destroy :: proc(e: ^Speculate_Entry, allocator: mem.Allocator) {
	if e == nil {
		return
	}
	if e.th != nil {
		thread.join(e.th)
		thread.destroy(e.th)
		e.th = nil
	}
	delete(e.id)
	delete(e.name)
	delete(e.args)
	delete(e.result)
	delete(e.err)
	free(e, allocator)
}

speculate_pool_destroy :: proc(pool: ^Speculate_Pool) {
	if pool == nil {
		return
	}
	speculate_discard_all(pool)
	sync.mutex_lock(&pool.mu)
	entries := pool.entries[:]
	pool.entries = {}
	sync.mutex_unlock(&pool.mu)
	for e in entries {
		speculate_entry_destroy(e, pool.allocator)
	}
	delete(entries)
	delete(pool.mode)
	pool^ = {}
}

speculate_stop_admit :: proc(pool: ^Speculate_Pool) {
	if pool == nil {
		return
	}
	sync.mutex_lock(&pool.mu)
	pool.admit = false
	sync.mutex_unlock(&pool.mu)
}

speculate_discard_all :: proc(pool: ^Speculate_Pool) {
	if pool == nil {
		return
	}
	sync.mutex_lock(&pool.mu)
	pool.admit = false
	for e in pool.entries {
		sync.mutex_lock(&e.mu)
		if e.state == .Queued || e.state == .Running {
			e.state = .Cancelled
		}
		sync.mutex_unlock(&e.mu)
	}
	sync.mutex_unlock(&pool.mu)
}

speculate_find :: proc(pool: ^Speculate_Pool, id, name: string, args_hash: u64) -> ^Speculate_Entry {
	for e in pool.entries {
		if e.args_hash == args_hash && e.name == name && e.id == id {
			return e
		}
	}
	return nil
}

speculate_find_by_id :: proc(pool: ^Speculate_Pool, id: string) -> ^Speculate_Entry {
	for e in pool.entries {
		if e.id == id {
			return e
		}
	}
	return nil
}

speculate_join_entry :: proc(e: ^Speculate_Entry) {
	if e == nil {
		return
	}
	for {
		sync.mutex_lock(&e.mu)
		st := e.state
		th := e.th
		if st == .Ready || st == .Failed || st == .Cancelled {
			e.th = nil
			sync.mutex_unlock(&e.mu)
			if th != nil {
				thread.join(th)
				thread.destroy(th)
			}
			return
		}
		// Queued or Running: join if handle exists, else wait for start.
		e.th = nil
		sync.mutex_unlock(&e.mu)
		if th != nil {
			thread.join(th)
			thread.destroy(th)
			continue
		}
		time.sleep(1 * time.Millisecond)
	}
}
