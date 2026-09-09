// SPDX-License-Identifier: 0BSD
/*
Drop last N user turns from session history with backup.
*/

package session

import "core:fmt"
import "core:strings"
import "nullray:provider"
import "nullray:store"

drop_start_index :: proc(msgs: []provider.Message, pairs: int) -> int {
	if pairs <= 0 || len(msgs) == 0 {
		return -1
	}
	user_starts := make([dynamic]int, 0, 8, context.temp_allocator)
	for m, i in msgs {
		if m.role == .User {
			append(&user_starts, i)
		}
	}
	if len(user_starts) == 0 {
		return -1
	}
	if pairs >= len(user_starts) {
		return user_starts[0]
	}
	return user_starts[len(user_starts) - pairs]
}

session_backup_before_trim :: proc(s: ^Session, label: string) -> (path: string, ok: bool) {
	if s == nil || len(s.messages) == 0 {
		return "", false
	}
	return store.backup_transcript(s.session_path, s.messages[:], label)
}

session_drop_pairs :: proc(s: ^Session, pairs: int) -> bool {
	if s == nil {
		return false
	}
	if pairs <= 0 {
		session_set_status(s, "usage: /drop N")
		return false
	}
	if s.busy {
		session_set_status(s, "busy · stop first or wait")
		return false
	}
	start := drop_start_index(s.messages[:], pairs)
	if start < 0 || start >= len(s.messages) {
		session_set_status(s, fmt.tprintf("nothing to drop (have %d messages)", len(s.messages)))
		return false
	}
	backup, backed := session_backup_before_trim(s, "drop")
	for i in start ..< len(s.messages) {
		provider.destroy_message(s.messages[i])
	}
	resize(&s.messages, start)
	session_clear_streaming(s)
	session_maybe_persist(s)
	if backed {
		session_set_status(s, fmt.tprintf("dropped %d pair(s) · backup %s", pairs, backup))
	} else {
		session_set_status(s, fmt.tprintf("dropped %d pair(s)", pairs))
	}
	return true
}
