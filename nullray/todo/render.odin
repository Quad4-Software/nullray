// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Todo list rendering: full view for tools and /todo, compact open-items
block for per-turn prompt injection with the staleness warning.
*/

package todo

import "core:fmt"
import "core:strings"
import "core:sync"
import "nullray:constants"

@(private)
write_item_line :: proc(b: ^strings.Builder, s: ^Store, it: ^Item) {
	marker := status_marker(it.status)
	if item_blocked(s, it) && it.status != .Blocked {
		marker = "!"
	}
	fmt.sbprintf(b, "%s [%s] %s", it.id, marker, it.text)
	if len(it.blocked_on) > 0 {
		strings.write_string(b, " (blocked_on: ")
		for ref, i in it.blocked_on {
			if i > 0 {
				strings.write_byte(b, ',')
			}
			strings.write_string(b, ref)
		}
		strings.write_byte(b, ')')
	}
	strings.write_byte(b, '\n')
}

// Full rendered list for todo_list, /todo, and mutation confirmations.
list_view :: proc(session_id: string, allocator := context.allocator) -> string {
	sync.mutex_lock(&g_mu)
	defer sync.mutex_unlock(&g_mu)
	s := store_for(session_id)
	b: strings.Builder
	strings.builder_init(&b, allocator)
	if len(s.items) == 0 {
		strings.write_string(&b, "(no tasks)\n")
		return strings.to_string(b)
	}
	fmt.sbprintf(&b, "tasks: %d open / %d total\n", open_count_locked(s), len(s.items))
	for &it in s.items {
		write_item_line(&b, s, &it)
		if len(it.note) > 0 {
			fmt.sbprintf(&b, "    note: %s\n", it.note)
		}
	}
	return strings.to_string(b)
}

// One line per open item, empty string when nothing is open.
summary_compact :: proc(session_id: string, allocator := context.allocator) -> string {
	sync.mutex_lock(&g_mu)
	defer sync.mutex_unlock(&g_mu)
	s := store_for(session_id)
	b: strings.Builder
	strings.builder_init(&b, allocator)
	for &it in s.items {
		if !is_open(&it) {
			continue
		}
		write_item_line(&b, s, &it)
	}
	return strings.to_string(b)
}

/*
Anti-forget injection block appended to the last user message of each
outbound turn. Empty when disabled or nothing is open. The stale warning
appears after TODO_STALE_NUDGE_TURNS turns without a task tool call.
*/
prompt_block :: proc(session_id: string, allocator := context.allocator) -> string {
	if !enabled() {
		return ""
	}
	sync.mutex_lock(&g_mu)
	defer sync.mutex_unlock(&g_mu)
	s := store_for(session_id)
	if open_count_locked(s) == 0 {
		return ""
	}
	b: strings.Builder
	strings.builder_init(&b, allocator)
	strings.write_string(&b, "<open_tasks>\n")
	for &it in s.items {
		if !is_open(&it) {
			continue
		}
		write_item_line(&b, s, &it)
	}
	if s.turns_since_touch >= constants.TODO_STALE_NUDGE_TURNS {
		fmt.sbprintf(
			&b,
			"(stale: %d turns without a task update - re-read and update or mark done)\n",
			s.turns_since_touch,
		)
	}
	strings.write_string(&b, "Keep this list current: call todo_write/todo_update when tasks change state.\n")
	strings.write_string(&b, "</open_tasks>")
	return strings.to_string(b)
}
