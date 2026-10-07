// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Todo mutations: add, update, and the todo_write full-sync. Every mutation
runs post_mutation to reset the staleness counter, raise the completion
notice when the last open item closes, and persist the store.
*/

package todo

import "core:fmt"
import "core:strings"
import "core:sync"
import "nullray:constants"

// Shared tail for every mutation: refresh counters, notice flag, persist.
@(private)
post_mutation :: proc(s: ^Store, session_id: string) {
	s.turns_since_touch = 0
	if len(s.items) > 0 && open_count_locked(s) == 0 {
		s.completion_notice = true
	}
	if len(session_id) > 0 {
		save_store(s, session_id)
	}
}

@(private)
clone_strings :: proc(src: []string, allocator := context.allocator) -> [dynamic]string {
	out := make([dynamic]string, 0, len(src), allocator)
	for v in src {
		append(&out, strings.clone(v, allocator))
	}
	return out
}

add :: proc(session_id, text: string, blocked_on: []string, allocator := context.allocator) -> (id: string, err: string) {
	trimmed := strings.trim_space(text)
	if len(trimmed) == 0 {
		return "", strings.clone("todo text is empty", allocator)
	}
	sync.mutex_lock(&g_mu)
	defer sync.mutex_unlock(&g_mu)
	s := store_for(session_id)
	if len(s.items) >= constants.TODO_MAX_ITEMS {
		return "", fmt.aprintf("todo list is full (max %d items)", constants.TODO_MAX_ITEMS, allocator = allocator)
	}
	nid, nseq := fresh_id(s, store_alloc())
	for dep in blocked_on {
		if dep == nid {
			delete(nid, store_alloc())
			return "", strings.clone("todo item cannot depend on itself", allocator)
		}
	}
	it := Item{
		id = nid,
		text = strings.clone(trimmed, store_alloc()),
		status = .Todo,
		blocked_on = clone_strings(blocked_on, store_alloc()),
		updated_epoch = now_epoch(),
		seq = nseq,
	}
	append(&s.items, it)
	post_mutation(s, session_id)
	return strings.clone(it.id, allocator), ""
}

update :: proc(
	session_id, id, status_raw, note: string,
	note_set: bool,
	blocked_on: []string,
	blocked_on_set: bool,
	allocator := context.allocator,
) -> (err: string) {
	sync.mutex_lock(&g_mu)
	defer sync.mutex_unlock(&g_mu)
	s := store_for(session_id)
	it := find_item(s, id)
	if it == nil {
		return fmt.aprintf("no todo item with id %s", id, allocator = allocator)
	}
	// Validate before mutating so a refused call leaves the item untouched.
	st: Status
	if len(status_raw) > 0 {
		parsed, ok := status_from_string(status_raw)
		if !ok {
			return fmt.aprintf("bad status %q (todo|in_progress|done|blocked|cancelled)", status_raw, allocator = allocator)
		}
		st = parsed
	}
	if blocked_on_set {
		for b in blocked_on {
			if b == it.id {
				return fmt.aprintf("todo item %s cannot depend on itself", it.id, allocator = allocator)
			}
		}
	}
	if len(status_raw) > 0 {
		it.status = st
	}
	if note_set {
		delete(it.note, store_alloc())
		it.note = strings.clone(note, store_alloc())
	}
	if blocked_on_set {
		for b in it.blocked_on {
			delete(b, store_alloc())
		}
		delete(it.blocked_on)
		it.blocked_on = clone_strings(blocked_on, store_alloc())
	}
	it.updated_epoch = now_epoch()
	post_mutation(s, session_id)
	return ""
}

/*
Full list sync. Each incoming entry matches an existing item by id first,
then by exact text on open items, unmatched entries become new items with
fresh tN ids. Existing items absent from the payload are marked cancelled,
not deleted, so history and ids stay stable.
*/
sync_items :: proc(session_id: string, incoming: []Sync_Item, allocator := context.allocator) -> (err: string) {
	if len(incoming) > constants.TODO_MAX_ITEMS {
		return fmt.aprintf("todo payload too large (max %d items)", constants.TODO_MAX_ITEMS, allocator = allocator)
	}
	sync.mutex_lock(&g_mu)
	defer sync.mutex_unlock(&g_mu)
	s := store_for(session_id)

	// Keyed by id string (borrowed, map dies with temp_allocator) because
	// appends can reallocate s.items and dangle ^Item keys.
	seen := make(map[string]bool, len(incoming), context.temp_allocator)

	// Validate everything before mutating: a bad status or self-dependency
	// deep in the payload must not leave a half-applied sync in memory or on
	// disk. The count pass mirrors the main loop's skip rule (unknown id or
	// no text match plus blank text is dropped, not created) so the cap
	// check counts the same set the apply pass would add.
	new_count := 0
	for inc in incoming {
		target: ^Item
		if len(inc.id) > 0 {
			target = find_item(s, inc.id)
		}
		if target == nil && len(inc.text) > 0 {
			target = find_open_by_text(s, inc.text)
		}
		if len(inc.status) > 0 {
			if _, ok := status_from_string(inc.status); !ok {
				return fmt.aprintf("bad status %q (todo|in_progress|done|blocked|cancelled)", inc.status, allocator = allocator)
			}
		}
		if inc.blocked_on_set {
			for b in inc.blocked_on {
				if (target != nil && b == target.id) || (len(inc.id) > 0 && b == inc.id) {
					return fmt.aprintf("todo item %s cannot depend on itself", b, allocator = allocator)
				}
			}
		}
		if target == nil {
			if len(strings.trim_space(inc.text)) == 0 {
				continue
			}
			new_count += 1
		}
	}
	if len(s.items) + new_count > constants.TODO_MAX_ITEMS {
		return fmt.aprintf("todo sync would exceed %d items", constants.TODO_MAX_ITEMS, allocator = allocator)
	}

	for inc in incoming {
		target: ^Item
		if len(inc.id) > 0 {
			target = find_item(s, inc.id)
		}
		if target == nil && len(inc.text) > 0 {
			target = find_open_by_text(s, inc.text)
		}
		if target == nil {
			text := strings.trim_space(inc.text)
			if len(text) == 0 {
				continue
			}
			nid, nseq := fresh_id(s, store_alloc())
			it := Item{
				id = nid,
				text = strings.clone(text, store_alloc()),
				status = .Todo,
				seq = nseq,
			}
			append(&s.items, it)
			target = &s.items[len(s.items) - 1]
		}
		if len(inc.text) > 0 && strings.trim_space(inc.text) != target.text {
			delete(target.text, store_alloc())
			target.text = strings.clone(strings.trim_space(inc.text), store_alloc())
		}
		if len(inc.status) > 0 {
			// Pre-validated above, the apply pass never fails mid-loop.
			st, _ := status_from_string(inc.status)
			target.status = st
		}
		if inc.note_set {
			delete(target.note, store_alloc())
			target.note = strings.clone(inc.note, store_alloc())
		}
		if inc.blocked_on_set {
			for b in target.blocked_on {
				delete(b, store_alloc())
			}
			delete(target.blocked_on)
			// The pre-pass refuses self-deps on resolvable targets, a fresh
			// id landing inside blocked_on is dropped here instead.
			deps := make([dynamic]string, 0, len(inc.blocked_on), store_alloc())
			for b in inc.blocked_on {
				if b == target.id {
					continue
				}
				append(&deps, strings.clone(b, store_alloc()))
			}
			target.blocked_on = deps
		}
		target.updated_epoch = now_epoch()
		seen[target.id] = true
	}

	for &it in s.items {
		if is_open(&it) && !seen[it.id] {
			it.status = .Cancelled
			it.updated_epoch = now_epoch()
		}
	}
	post_mutation(s, session_id)
	return ""
}
