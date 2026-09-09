// SPDX-License-Identifier: 0BSD
/*
Read-only speculative tool pool: submit, join by hash, discard on miss/cancel.
*/

package tools

import "core:fmt"
import "core:hash"
import "core:mem"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"
import "nullray:constants"
import "nullray:hooks"

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
		"read_man", "apropos",
		"list_skills", "load_skill",
		"memory_get", "memory_list", "memory_search",
		"read_artifact", "grep_artifact",
		"vcs_status", "vcs_diff", "vcs_log", "vcs_pr_view",
		"audit_structure", "audit_actions", "audit_dockerfile",
		"audit_compose", "audit_owasp", "audit_deps":
		return true
	}
	return false
}

speculate_args_hash :: proc(args: string) -> u64 {
	return hash.fnv64a(transmute([]byte)args)
}

speculate_key_id :: proc(id: string, idx: int, allocator := context.allocator) -> string {
	if len(id) > 0 {
		return strings.clone(id, allocator)
	}
	return fmt.aprintf("#%d", idx, allocator = allocator)
}

speculate_leading_prefix_len :: proc(names: []string) -> int {
	n := 0
	for name in names {
		if !speculate_allowlisted(name) {
			break
		}
		n += 1
	}
	return n
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

speculate_try_start_locked :: proc(pool: ^Speculate_Pool) {
	for e in pool.entries {
		if pool.active >= pool.max_parallel {
			return
		}
		sync.mutex_lock(&e.mu)
		ready := e.state == .Queued && e.th == nil
		if ready {
			e.state = .Running
		}
		sync.mutex_unlock(&e.mu)
		if !ready {
			continue
		}
		pool.active += 1
		job := new(Speculate_Job, pool.allocator)
		job.pool = pool
		job.entry = e
		// Create first, publish handle, then start so take never races a nil th.
		th := thread.create(proc(t: ^thread.Thread) {
			fn := cast(proc(rawptr))t.data
			data := t.user_args[0]
			fn(data)
		}, .Normal)
		if th == nil {
			pool.active -= 1
			sync.mutex_lock(&e.mu)
			e.state = .Failed
			e.err = strings.clone("speculate thread create failed", pool.allocator)
			sync.mutex_unlock(&e.mu)
			free(job, pool.allocator)
			continue
		}
		th.data = rawptr(speculate_worker)
		th.user_index = 1
		th.user_args[0] = job
		th.init_context = context
		sync.mutex_lock(&e.mu)
		e.th = th
		sync.mutex_unlock(&e.mu)
		thread.start(th)
	}
}

speculate_worker :: proc(data: rawptr) {
	job := cast(^Speculate_Job)data
	pool := job.pool
	entry := job.entry
	alloc := pool.allocator
	free(job, alloc)

	sync.mutex_lock(&entry.mu)
	cancelled := entry.state == .Cancelled
	sync.mutex_unlock(&entry.mu)
	if cancelled {
		sync.mutex_lock(&pool.mu)
		pool.active -= 1
		speculate_try_start_locked(pool)
		sync.mutex_unlock(&pool.mu)
		return
	}

	sync.mutex_lock(&entry.mu)
	name := strings.clone(entry.name, alloc)
	args := strings.clone(entry.args, alloc)
	sync.mutex_unlock(&entry.mu)
	defer {
		delete(name)
		delete(args)
	}

	start := time.tick_now()
	tool_result, tool_err := "", ""
	blocked_pre := false
	pre := hooks.run(.PreToolUse, name, args, alloc)
	if pre.blocked {
		tool_err = pre.message
		blocked_pre = true
	} else {
		delete(pre.message)
		tool_result, tool_err = run(pool.reg, name, args, pool.mode, alloc, pool.tool_allow)
	}
	elapsed := time.duration_milliseconds(time.tick_since(start))

	sync.mutex_lock(&entry.mu)
	entry.pre_ran = true
	entry.blocked_pre = blocked_pre
	if entry.state == .Cancelled {
		delete(tool_result)
		delete(tool_err)
	} else {
		entry.result = tool_result
		entry.err = tool_err
		entry.duration_ms = i64(elapsed)
		if len(tool_err) > 0 {
			entry.state = .Failed
		} else {
			entry.state = .Ready
		}
	}
	sync.mutex_unlock(&entry.mu)

	sync.mutex_lock(&pool.mu)
	pool.active -= 1
	speculate_try_start_locked(pool)
	sync.mutex_unlock(&pool.mu)
}

speculate_submit :: proc(
	pool: ^Speculate_Pool,
	id, name, args: string,
	allocator := context.allocator,
) -> bool {
	_ = allocator
	if pool == nil {
		return false
	}
	if !speculate_allowlisted(name) {
		return false
	}
	if !tool_name_in_allow(name, pool.tool_allow) {
		return false
	}
	sync.mutex_lock(&pool.mu)
	defer sync.mutex_unlock(&pool.mu)
	if !pool.admit {
		return false
	}
	ah := speculate_args_hash(args)
	if existing := speculate_find(pool, id, name, ah); existing != nil {
		return true
	}
	e := new(Speculate_Entry, pool.allocator)
	if e == nil {
		return false
	}
	e^ = {}
	e.id = strings.clone(id, pool.allocator)
	e.name = strings.clone(name, pool.allocator)
	e.args = strings.clone(args, pool.allocator)
	e.args_hash = ah
	e.state = .Queued
	append(&pool.entries, e)
	speculate_try_start_locked(pool)
	return true
}

Speculate_Take :: struct {
	ok:          bool,
	hit:         bool,
	result:      string,
	err:         string,
	pre_ran:     bool,
	blocked_pre: bool,
	duration_ms: i64,
}

speculate_take :: proc(
	pool: ^Speculate_Pool,
	id, name, args: string,
	allocator := context.allocator,
) -> Speculate_Take {
	_ = allocator
	out: Speculate_Take
	if pool == nil || !speculate_allowlisted(name) {
		return out
	}
	ah := speculate_args_hash(args)
	sync.mutex_lock(&pool.mu)
	entry := speculate_find(pool, id, name, ah)
	sync.mutex_unlock(&pool.mu)
	if entry == nil {
		return out
	}

	speculate_join_entry(entry)

	sync.mutex_lock(&entry.mu)
	st := entry.state
	if st == .Cancelled || (st != .Ready && st != .Failed) {
		sync.mutex_unlock(&entry.mu)
		return out
	}
	out.ok = true
	out.hit = true
	out.pre_ran = entry.pre_ran
	out.blocked_pre = entry.blocked_pre
	out.duration_ms = entry.duration_ms
	out.result = entry.result
	out.err = entry.err
	entry.result = ""
	entry.err = ""
	sync.mutex_unlock(&entry.mu)
	return out
}

/*
True when an entry exists for this id with a different args hash (real speculation miss).
*/
speculate_hash_miss :: proc(pool: ^Speculate_Pool, id, name, args: string) -> bool {
	if pool == nil {
		return false
	}
	ah := speculate_args_hash(args)
	sync.mutex_lock(&pool.mu)
	defer sync.mutex_unlock(&pool.mu)
	e := speculate_find_by_id(pool, id)
	if e == nil {
		return false
	}
	return e.name == name && e.args_hash != ah
}

speculate_has :: proc(pool: ^Speculate_Pool, id, name, args: string) -> bool {
	if pool == nil {
		return false
	}
	ah := speculate_args_hash(args)
	sync.mutex_lock(&pool.mu)
	defer sync.mutex_unlock(&pool.mu)
	return speculate_find(pool, id, name, ah) != nil
}
