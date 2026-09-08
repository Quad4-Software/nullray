// SPDX-License-Identifier: 0BSD
/*
Provider-facing LID projection and prepare write-back into the session transcript.
*/

package session

import "core:strings"
import "nullray:agent"
import "nullray:provider"

/*
Build the model view from the full session transcript.
System messages are prepended by the caller. Returns owned messages.
*/
session_project_messages :: proc(
	s: ^Session,
	allocator := context.allocator,
) -> [dynamic]provider.Message {
	out := make([dynamic]provider.Message, 0, len(s.messages), allocator)
	if !agent.lid_enabled() || len(s.messages) == 0 {
		for m in s.messages {
			append(&out, provider.clone_message(m, allocator))
		}
		return out
	}

	max_user_turns := agent.projection_user_turns()
	max_tool_stubs := agent.projection_tool_stubs()

	user_asst_idxs := make([dynamic]int, context.temp_allocator)
	tool_idxs := make([dynamic]int, context.temp_allocator)
	for m, i in s.messages {
		switch m.role {
		case .User, .Assistant:
			append(&user_asst_idxs, i)
		case .Tool:
			append(&tool_idxs, i)
		case .System:
		}
	}

	keep_ua_start := 0
	if len(user_asst_idxs) > max_user_turns * 2 {
		keep_ua_start = len(user_asst_idxs) - max_user_turns * 2
	}
	keep_tool_start := 0
	if len(tool_idxs) > max_tool_stubs {
		keep_tool_start = len(tool_idxs) - max_tool_stubs
	}

	keep_flags := make([]bool, len(s.messages), context.temp_allocator)
	for ti in keep_ua_start ..< len(user_asst_idxs) {
		keep_flags[user_asst_idxs[ti]] = true
	}
	for ti in keep_tool_start ..< len(tool_idxs) {
		keep_flags[tool_idxs[ti]] = true
	}
	for i := len(s.messages) - 1; i >= 0; i -= 1 {
		if s.messages[i].role == .User {
			keep_flags[i] = true
			break
		}
	}

	stub_budget := agent.compact_chars_budget() / 8
	if stub_budget < 1_000 {
		stub_budget = 1_000
	}
	for m, i in s.messages {
		if !keep_flags[i] {
			continue
		}
		cloned := provider.clone_message(m, allocator)
		if cloned.role == .Tool && len(cloned.content) > stub_budget {
			stub := agent.tool_clear_stub(cloned, allocator)
			delete(cloned.content)
			cloned.content = stub
		}
		append(&out, cloned)
	}
	return out
}

/*
Persist prepare mutations into s.messages so the next turn does not re-summarize fat history.
*/
session_writeback_prepare :: proc(s: ^Session, flat: []provider.Message, stats: agent.Prepare_Stats) -> bool {
	if s == nil || len(flat) == 0 {
		return false
	}
	if stats.compacted {
		for m in s.messages {
			provider.destroy_message(m)
		}
		clear(&s.messages)
		for m in flat {
			if m.role == .System {
				continue
			}
			append(&s.messages, provider.clone_message(m))
		}
		session_maybe_persist(s)
		return true
	}
	if stats.cleared == 0 {
		return false
	}
	changed := false
	for fm in flat {
		if fm.role != .Tool {
			continue
		}
		for i in 0 ..< len(s.messages) {
			sm := s.messages[i]
			if sm.role != .Tool {
				continue
			}
			same_id := len(fm.tool_call_id) > 0 && fm.tool_call_id == sm.tool_call_id
			same_name := len(fm.tool_call_id) == 0 && fm.name == sm.name && len(fm.name) > 0
			if !same_id && !same_name {
				continue
			}
			if sm.content == fm.content {
				break
			}
			delete(s.messages[i].content)
			s.messages[i].content = strings.clone(fm.content)
			changed = true
			break
		}
	}
	if changed {
		session_maybe_persist(s)
	}
	return changed
}

/*
On mode / plan->edit transitions, shrink the transcript toward digests and stubs.
*/
session_phase_reset_provider_window :: proc(s: ^Session) {
	if s == nil || !agent.lid_enabled() {
		return
	}
	_ = agent.clear_old_tool_results(&s.messages, 2)
	budget := agent.compact_chars_budget()
	if budget <= 0 {
		session_maybe_persist(s)
		return
	}
	if agent.messages_content_chars(s.messages[:]) <= budget {
		session_maybe_persist(s)
		return
	}
	projected := session_project_messages(s)
	for m in s.messages {
		provider.destroy_message(m)
	}
	clear(&s.messages)
	for m in projected {
		append(&s.messages, m)
	}
	delete(projected)
	session_maybe_persist(s)
}
