// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Session scrub/forget: rewrite in-memory messages (and disk if persisting)
to strip secrets or drop matching content after a paste mistake.
*/

package session

import "core:fmt"
import "core:strings"
import "nullray:provider"
import "nullray:sandbox"

// Re-run secret redaction on every stored message. Returns how many were changed.
session_scrub_all :: proc(s: ^Session) -> int {
	if s == nil {
		return 0
	}
	n := 0
	for &m in s.messages {
		if session_scrub_message(&m) {
			n += 1
		}
	}
	if n > 0 {
		session_maybe_persist(s)
	}
	return n
}

// Drop the last user turn (and following assistant/tool until next user).
session_forget_last_user :: proc(s: ^Session) -> int {
	if s == nil || len(s.messages) == 0 {
		return 0
	}
	// Find last user index.
	ui := -1
	for i := len(s.messages) - 1; i >= 0; i -= 1 {
		if s.messages[i].role == .User {
			ui = i
			break
		}
	}
	if ui < 0 {
		return 0
	}
	removed := 0
	for i := len(s.messages) - 1; i >= ui; i -= 1 {
		provider.destroy_message(s.messages[i])
		ordered_remove(&s.messages, i)
		removed += 1
	}
	session_maybe_persist(s)
	return removed
}

// Replace content that contains needle (case-insensitive) with a redacted stub.
session_forget_matching :: proc(s: ^Session, needle: string) -> int {
	if s == nil || len(needle) == 0 {
		return 0
	}
	nlow := strings.to_lower(needle, context.temp_allocator)
	n := 0
	for &m in s.messages {
		if len(m.content) == 0 {
			continue
		}
		clow := strings.to_lower(m.content, context.temp_allocator)
		if strings.contains(clow, nlow) {
			old := m.content
			m.content = strings.clone("[forgotten]")
			delete(old)
			n += 1
		}
		if len(m.reasoning) > 0 {
			rlow := strings.to_lower(m.reasoning, context.temp_allocator)
			if strings.contains(rlow, nlow) {
				old := m.reasoning
				m.reasoning = strings.clone("[forgotten]")
				delete(old)
				n += 1
			}
		}
	}
	if n > 0 {
		session_maybe_persist(s)
	}
	return n
}

@(private)
session_scrub_message :: proc(m: ^provider.Message) -> bool {
	changed := false
	if len(m.content) > 0 {
		safe := sandbox.redact_secrets(m.content, context.allocator)
		if safe != m.content {
			delete(m.content)
			m.content = safe
			changed = true
		} else {
			delete(safe)
		}
	}
	if len(m.reasoning) > 0 {
		safe := sandbox.redact_secrets(m.reasoning, context.allocator)
		if safe != m.reasoning {
			delete(m.reasoning)
			m.reasoning = safe
			changed = true
		} else {
			delete(safe)
		}
	}
	return changed
}

session_scrub_status :: proc(s: ^Session, kind: string, n: int) -> string {
	return fmt.tprintf("scrub %s: %d", kind, n)
}
