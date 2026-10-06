// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Long-horizon session task list. Stores are keyed by session id, shared in
memory, and persisted under .nullray/todos/<session>.json. Two anti-forget
mechanisms: prompt_block injects open items into the outbound request each
turn, and turns_since_touch feeds a staleness warning when the model stops
updating the list.
*/

package todo

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "core:time"
import "nullray:constants"

Status :: enum {
	Todo,
	In_Progress,
	Done,
	Blocked,
	Cancelled,
}

Item :: struct {
	id:           string,
	text:         string,
	status:       Status,
	blocked_on:   [dynamic]string,
	note:         string,
	updated_epoch: i64,
	seq:          int,
}

Store :: struct {
	// Heap clone of the session id used as the g_stores key so unload can
	// free it; map delete_key does not release key strings.
	key:               string,
	items:             [dynamic]Item,
	next_seq:          int,
	turns_since_touch: int,
	completion_notice: bool,
}

// One entry of a todo_write sync payload. Empty text on an id-matched entry
// keeps the existing text.
Sync_Item :: struct {
	id:            string,
	text:          string,
	status:        string,
	blocked_on:    []string,
	blocked_on_set: bool,
	note:          string,
	note_set:      bool,
}

Bind :: struct {
	id:        string,
	set:       bool,
	read_only: bool,
}

@(thread_local)
tls_bind: Bind

g_mu: sync.Mutex
g_stores: map[string]^Store

// Store memory lives past any single caller context and crosses test
// tracking allocators, so every allocation owned by g_stores uses the
// heap allocator on both alloc and free.
store_alloc :: proc() -> runtime.Allocator {
	return runtime.heap_allocator()
}

enabled :: proc() -> bool {
	if v, ok := os.lookup_env(constants.ENV_TODO, context.temp_allocator); ok {
		switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
		case "0", "false", "no", "off", "disable", "disabled":
			return false
		}
	}
	return true
}

/*
Bind the todo session for this thread so tool procs (which receive no
session argument) resolve the right store. Restore with unbind(prev).
read_only marks child/subagent turns: they may read the list but writes are
refused.
*/
bind :: proc(id: string, read_only := false) -> (prev: Bind) {
	prev = tls_bind
	tls_bind = {}
	tls_bind.set = true
	tls_bind.read_only = read_only
	if len(id) > 0 {
		tls_bind.id = strings.clone(id)
	}
	return prev
}

unbind :: proc(prev: Bind) {
	delete(tls_bind.id)
	tls_bind = prev
}

// Borrowed thread-local id; empty when unbound.
current_session :: proc() -> string {
	if !tls_bind.set {
		return ""
	}
	return tls_bind.id
}

writes_blocked :: proc() -> bool {
	return tls_bind.set && tls_bind.read_only
}

@(private)
find_item :: proc(s: ^Store, id: string) -> ^Item {
	for &it in s.items {
		if it.id == id {
			return &it
		}
	}
	return nil
}

@(private)
find_open_by_text :: proc(s: ^Store, text: string) -> ^Item {
	for &it in s.items {
		if it.text == text && it.status != .Done && it.status != .Cancelled {
			return &it
		}
	}
	return nil
}

@(private)
is_open :: proc(it: ^Item) -> bool {
	return it.status == .Todo || it.status == .In_Progress || it.status == .Blocked
}

@(private)
open_count_locked :: proc(s: ^Store) -> int {
	n := 0
	for &it in s.items {
		if is_open(&it) {
			n += 1
		}
	}
	return n
}

open_count :: proc(session_id: string) -> int {
	sync.mutex_lock(&g_mu)
	defer sync.mutex_unlock(&g_mu)
	s := store_for(session_id)
	return open_count_locked(s)
}

// Blocked when marked so, or when any live blocked_on ref is unfinished.
@(private)
item_blocked :: proc(s: ^Store, it: ^Item) -> bool {
	if it.status == .Blocked {
		return true
	}
	if it.status == .Done || it.status == .Cancelled {
		return false
	}
	for ref in it.blocked_on {
		tgt := find_item(s, ref)
		if tgt != nil && tgt.status != .Done && tgt.status != .Cancelled {
			return true
		}
	}
	return false
}

status_from_string :: proc(raw: string) -> (Status, bool) {
	switch strings.to_lower(strings.trim_space(raw), context.temp_allocator) {
	case "todo", "open", "pending":
		return .Todo, true
	case "in_progress", "in-progress", "inprogress", "doing", "wip":
		return .In_Progress, true
	case "done", "complete", "completed":
		return .Done, true
	case "blocked":
		return .Blocked, true
	case "cancelled", "canceled":
		return .Cancelled, true
	}
	return .Todo, false
}

status_name :: proc(st: Status) -> string {
	switch st {
	case .Todo:
		return "todo"
	case .In_Progress:
		return "in_progress"
	case .Done:
		return "done"
	case .Blocked:
		return "blocked"
	case .Cancelled:
		return "cancelled"
	}
	return "todo"
}

// ASCII markers only: space, tilde, x, bang, dash.
@(private)
status_marker :: proc(st: Status) -> string {
	switch st {
	case .Todo:
		return " "
	case .In_Progress:
		return "~"
	case .Done:
		return "x"
	case .Blocked:
		return "!"
	case .Cancelled:
		return "-"
	}
	return " "
}

@(private)
item_destroy :: proc(it: ^Item) {
	delete(it.id, store_alloc())
	delete(it.text, store_alloc())
	for b in it.blocked_on {
		delete(b, store_alloc())
	}
	delete(it.blocked_on)
	delete(it.note, store_alloc())
}

store_destroy :: proc(s: ^Store) {
	if s == nil {
		return
	}
	for &it in s.items {
		item_destroy(&it)
	}
	delete(s.items)
	delete(s.key, store_alloc())
	free(s, store_alloc())
}

store_for :: proc(session_id: string) -> ^Store {
	// Caller holds g_mu.
	if s, ok := g_stores[session_id]; ok {
		return s
	}
	if g_stores == nil {
		g_stores = make(map[string]^Store, store_alloc())
	}
	s := new(Store, store_alloc())
	s.items = make([dynamic]Item, allocator = store_alloc())
	s.next_seq = 1
	s.key = strings.clone(session_id, store_alloc())
	g_stores[s.key] = s
	if len(session_id) > 0 {
		load_store(s, session_id)
	}
	return s
}

// Drop the in-memory store so the next access reloads from disk. The file
// is left alone; tests use this for roundtrip checks.
unload :: proc(session_id: string) {
	sync.mutex_lock(&g_mu)
	defer sync.mutex_unlock(&g_mu)
	if s, ok := g_stores[session_id]; ok {
		delete_key(&g_stores, session_id)
		// store_destroy releases s.key, the cloned map key bytes.
		store_destroy(s)
	}
}

@(private)
fresh_id :: proc(s: ^Store, allocator := context.allocator) -> (id: string, seq: int) {
	for {
		n := s.next_seq
		s.next_seq += 1
		candidate := fmt.aprintf("t%d", n, allocator = allocator)
		if find_item(s, candidate) == nil {
			return candidate, n
		}
		delete(candidate, allocator)
	}
}

@(private)
now_epoch :: proc() -> i64 {
	return time.time_to_unix(time.now())
}

mark_tool_use :: proc(session_id: string) {
	sync.mutex_lock(&g_mu)
	defer sync.mutex_unlock(&g_mu)
	s := store_for(session_id)
	s.turns_since_touch = 0
}

// Called once per agent turn. Only counts turns while work is open so a
// completed or empty list never goes "stale".
mark_turn :: proc(session_id: string) {
	sync.mutex_lock(&g_mu)
	defer sync.mutex_unlock(&g_mu)
	s := store_for(session_id)
	if open_count_locked(s) > 0 {
		s.turns_since_touch += 1
	} else {
		s.turns_since_touch = 0
	}
}

turns_since_touch :: proc(session_id: string) -> int {
	sync.mutex_lock(&g_mu)
	defer sync.mutex_unlock(&g_mu)
	s := store_for(session_id)
	return s.turns_since_touch
}

// One-shot flag raised when the last open item closes. The turn loop takes
// it to emit a "tasks complete" status.
take_completed_notice :: proc(session_id: string) -> bool {
	sync.mutex_lock(&g_mu)
	defer sync.mutex_unlock(&g_mu)
	s := store_for(session_id)
	out := s.completion_notice
	s.completion_notice = false
	return out
}
