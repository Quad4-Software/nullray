// SPDX-License-Identifier: 0BSD
package session

import "core:os"
import "core:strings"
import "nullray:agent"
import "nullray:constants"
import "nullray:provider"

session_push_user :: proc(s: ^Session, text: string) {
	if s.mode_policy == .Auto {
		suggested := agent.auto_suggest_mode(text)
		if suggested != s.agent_mode {
			session_set_mode(s, suggested)
		}
	}
	cap_messages(s)
	append(&s.messages, provider.Message{role = .User, content = strings.clone(text)})
	session_maybe_persist(s)
}

session_push_assistant :: proc(s: ^Session, text: string, reasoning := "") {
	cap_messages(s)
	append(&s.messages, provider.Message{
		role = .Assistant,
		content = strings.clone(text),
		reasoning = strings.clone(reasoning),
	})
	session_maybe_persist(s)
}

/*
Trim the latest assistant content for the next provider turn. Full text can
stay in a caller-owned copy (hunt explore output). Caps oracle-phase prompt growth.
*/
session_cap_last_assistant :: proc(s: ^Session, max_chars: int) {
	if s == nil || max_chars <= 0 {
		return
	}
	for i := len(s.messages) - 1; i >= 0; i -= 1 {
		if s.messages[i].role != .Assistant {
			continue
		}
		old := s.messages[i].content
		if len(old) <= max_chars {
			return
		}
		cut := max_chars
		for j := max_chars; j > max_chars / 2; j -= 1 {
			if old[j - 1] == '\n' {
				cut = j
				break
			}
		}
		s.messages[i].content = strings.concatenate(
			{old[:cut], "...[explore truncated for oracle phase]\n"},
			context.allocator,
		)
		delete(old)
		session_maybe_persist(s)
		return
	}
}

session_push_tool :: proc(s: ^Session, name, text: string) {
	cap_messages(s)
	append(&s.messages, provider.Message{
		role = .Tool,
		content = strings.clone(text),
		name = strings.clone(name),
	})
	session_maybe_persist(s)
}

@(private)
cap_messages :: proc(s: ^Session) {
	if len(s.messages) >= constants.MAX_MESSAGES {
		old := s.messages[0]
		provider.destroy_message(old)
		ordered_remove(&s.messages, 0)
	}
	session_trim_memory(s, mem_max_chars_from_env())
}

ephemeral_from_env :: proc() -> bool {
	if v, ok := os.lookup_env(constants.ENV_EPHEMERAL, context.temp_allocator); ok {
		switch strings.to_lower(v, context.temp_allocator) {
		case "1", "true", "yes", "on":
			return true
		}
	}
	return false
}

group_context_from_env :: proc() -> bool {
	if v, ok := os.lookup_env(constants.ENV_GROUP_CONTEXT, context.temp_allocator); ok {
		switch strings.to_lower(v, context.temp_allocator) {
		case "0", "false", "no", "off":
			return false
		}
	}
	return true
}
