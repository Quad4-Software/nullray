// SPDX-License-Identifier: 0BSD
/*
Conversation compaction helpers.
*/

package session

import "core:fmt"
import "core:strings"
import "nullray:agent"
import "nullray:provider"

session_compact_local :: proc(s: ^Session) -> bool {
	if len(s.messages) < 6 {
		return false
	}
	keep := 4
	drop_end := len(s.messages) - keep
	if drop_end <= 0 {
		return false
	}
	summary_b: strings.Builder
	strings.builder_init(&summary_b)
	strings.write_string(&summary_b, "Earlier conversation compacted:\n")
	for i in 0 ..< drop_end {
		m := s.messages[i]
		role := provider.role_string(m.role)
		snippet := m.content
		if len(snippet) > 240 {
			snippet = snippet[:240]
		}
		fmt.sbprintf(&summary_b, "- %s: %s\n", role, snippet)
	}
	kept := make([]provider.Message, keep)
	for i in 0 ..< keep {
		kept[i] = s.messages[drop_end + i]
	}
	for i in 0 ..< drop_end {
		provider.destroy_message(s.messages[i])
	}
	delete(s.messages)
	s.messages = make([dynamic]provider.Message)
	append(&s.messages, provider.Message{role = .User, content = strings.to_string(summary_b)})
	for m in kept {
		append(&s.messages, m)
	}
	delete(kept)
	session_set_status(s, "compacted")
	session_maybe_persist(s)
	return true
}

session_compact_with_provider :: proc(s: ^Session, p: ^provider.Provider) -> bool {
	if p == nil || len(s.messages) < 6 {
		return session_compact_local(s)
	}
	summary, ok := agent.compact_with_model(p, s.messages[:])
	if !ok {
		return session_compact_local(s)
	}
	keep := 4
	drop_end := max(0, len(s.messages) - keep)
	kept := make([dynamic]provider.Message, 0, keep)
	for i in drop_end ..< len(s.messages) {
		append(&kept, s.messages[i])
	}
	for i in 0 ..< drop_end {
		provider.destroy_message(s.messages[i])
	}
	delete(s.messages)
	s.messages = make([dynamic]provider.Message)
	append(&s.messages, provider.Message{
		role = .User,
		content = fmt.aprintf("Conversation summary (compacted):\n%s", summary),
	})
	delete(summary)
	for m in kept {
		append(&s.messages, m)
	}
	delete(kept)
	session_set_status(s, "compacted (model)")
	session_maybe_persist(s)
	return true
}

