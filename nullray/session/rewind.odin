// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
/rewind: restore last file checkpoint, truncate from a user-turn index,
and compact the dropped prefix (summarize from here).
*/

package session

import "core:fmt"
import "core:strings"
import "nullray:agent"
import "nullray:provider"
import "nullray:tools"

session_rewind :: proc(s: ^Session, pairs: int, p: ^provider.Provider) -> bool {
	if s == nil {
		return false
	}
	if s.busy {
		session_set_status(s, "busy · stop first or wait")
		return false
	}
	n := pairs
	if n <= 0 {
		n = 1
	}
	start := drop_start_index(s.messages[:], n)
	if start < 0 || start >= len(s.messages) {
		session_set_status(s, "nothing to rewind")
		return false
	}
	backup, backed := session_backup_before_trim(s, "rewind")
	dropped := s.messages[start:]
	summary := ""
	if p != nil && p.chat != nil && len(dropped) >= 2 {
		if text, ok := agent.compact_with_model(p, dropped); ok {
			summary = text
		}
	}
	if len(summary) == 0 {
		b: strings.Builder
		strings.builder_init(&b)
		strings.write_string(&b, "Goal:\n(rewind)\nFiles:\n(restored last checkpoint if any)\nErrors:\n(none)\nNext:\n(continue from here)\nPending steers:\n(none)\n")
		for m in dropped {
			role := provider.role_string(m.role)
			snip := m.content
			if len(snip) > 160 {
				snip = snip[:160]
			}
			fmt.sbprintf(&b, "- %s: %s\n", role, snip)
		}
		summary = strings.to_string(b)
	}
	keep := make([]provider.Message, start)
	for i in 0 ..< start {
		keep[i] = s.messages[i]
	}
	for i in start ..< len(s.messages) {
		provider.destroy_message(s.messages[i])
	}
	delete(s.messages)
	s.messages = make([dynamic]provider.Message)
	for m in keep {
		append(&s.messages, m)
	}
	delete(keep)
	append(&s.messages, provider.Message{
		role = .User,
		content = fmt.aprintf("Summarize from here (rewound):\n%s", summary),
	})
	delete(summary)
	session_clear_streaming(s)
	undo_msg, _ := tools.undo_last_write()
	session_maybe_persist(s)
	label := "rewound"
	if backed {
		label = fmt.tprintf("rewound %d pair(s) · backup %s", n, backup)
	} else {
		label = fmt.tprintf("rewound %d pair(s)", n)
	}
	if len(undo_msg) > 0 && undo_msg != "nothing to undo" {
		session_set_status(s, fmt.tprintf("%s · %s", label, undo_msg))
	} else {
		session_set_status(s, label)
	}
	delete(undo_msg)
	return true
}
