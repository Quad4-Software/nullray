// SPDX-License-Identifier: 0BSD
/*
Tool-result clearing and clear-then-compact context preparation.
*/

package session

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "nullray:agent"
import "nullray:constants"
import "nullray:provider"

compact_chars_from_env :: proc() -> int {
	if v, ok := os.lookup_env(constants.ENV_COMPACT_CHARS, context.temp_allocator); ok {
		n, n_ok := strconv.parse_int(v)
		if n_ok && n > 4_000 {
			return n
		}
		if n_ok && n == 0 {
			return 0
		}
	}
	return constants.COMPACT_CHARS_DEFAULT
}

tool_clear_keep_from_env :: proc() -> int {
	if v, ok := os.lookup_env(constants.ENV_TOOL_CLEAR_KEEP, context.temp_allocator); ok {
		n, n_ok := strconv.parse_int(v)
		if n_ok && n >= 1 {
			return n
		}
	}
	return constants.TOOL_CLEAR_KEEP_DEFAULT
}

messages_content_chars :: proc(msgs: []provider.Message) -> int {
	total := 0
	for m in msgs {
		total += len(m.content) + len(m.reasoning) + len(m.name)
		for tc in m.tool_calls {
			total += len(tc.name) + len(tc.arguments) + len(tc.id)
		}
	}
	return total
}

is_cleared_tool_content :: proc(content: string) -> bool {
	return strings.has_prefix(content, constants.TOOL_CLEAR_STUB_PREFIX)
}

looks_like_tool_error :: proc(content: string) -> bool {
	lower := strings.to_lower(content, context.temp_allocator)
	if strings.has_prefix(lower, "error") {
		return true
	}
	if strings.contains(lower, "failed:") {
		return true
	}
	if strings.contains(lower, "not allowed") {
		return true
	}
	if strings.contains(lower, "unknown tool") {
		return true
	}
	if strings.contains(lower, "permission_denied") || strings.contains(lower, "permission denied") {
		return true
	}
	return false
}

tool_clear_stub :: proc(m: provider.Message, allocator := context.allocator) -> string {
	name := m.name
	if len(name) == 0 {
		name = "tool"
	}
	return fmt.aprintf(
		"%s %s %d bytes; re-call if needed]",
		constants.TOOL_CLEAR_STUB_PREFIX,
		name,
		len(m.content),
		allocator = allocator,
	)
}

/*
Replace older tool payloads with stubs. Keeps the last `keep` tool messages raw.
Preserves recent error results (not cleared).
Operates in-place on owned message content.
*/
clear_old_tool_results :: proc(msgs: ^[dynamic]provider.Message, keep: int) -> int {
	if msgs == nil || keep < 0 {
		return 0
	}
	tool_idxs := make([dynamic]int, context.temp_allocator)
	for m, i in msgs {
		if m.role == .Tool {
			append(&tool_idxs, i)
		}
	}
	if len(tool_idxs) <= keep {
		return 0
	}
	cleared := 0
	cutoff := len(tool_idxs) - keep
	for ti in 0 ..< cutoff {
		i := tool_idxs[ti]
		m := msgs[i]
		if is_cleared_tool_content(m.content) {
			continue
		}
		if looks_like_tool_error(m.content) {
			continue
		}
		stub := tool_clear_stub(m)
		delete(m.content)
		msgs[i].content = stub
		cleared += 1
	}
	return cleared
}

/*
Clear-then-compact ladder for a flat message list about to be sent.
Mutates msgs in place. May call the provider for summarization.
*/
session_prepare_context :: proc(msgs: ^[dynamic]provider.Message, p: ^provider.Provider) {
	if msgs == nil {
		return
	}
	budget := compact_chars_from_env()
	if budget <= 0 {
		return
	}
	keep := tool_clear_keep_from_env()
	_ = clear_old_tool_results(msgs, keep)

	total := messages_content_chars(msgs[:])
	trigger := (budget * 70) / 100
	if trigger < 8_000 {
		trigger = budget
	}
	if total <= trigger {
		return
	}

	// Still over: clear more aggressively (keep 2)
	if keep > 2 {
		_ = clear_old_tool_results(msgs, 2)
		total = messages_content_chars(msgs[:])
		if total <= trigger {
			return
		}
	}

	if p == nil || p.chat == nil || len(msgs) < 6 {
		return
	}
	keep_n := constants.COMPACT_KEEP_MESSAGES
	if keep_n >= len(msgs) {
		return
	}
	drop_end := len(msgs) - keep_n
	if drop_end <= 1 {
		return
	}
	// Do not drop the leading system message
	start := 0
	if msgs[0].role == .System {
		start = 1
	}
	if start >= drop_end {
		return
	}

	to_summarize := msgs[start:drop_end]
	summary, ok := agent.compact_with_model(p, to_summarize)
	if !ok {
		return
	}
	kept_sys: [dynamic]provider.Message
	if start > 0 {
		append(&kept_sys, msgs[0])
	}
	kept_tail := make([dynamic]provider.Message, 0, keep_n, context.temp_allocator)
	for i in drop_end ..< len(msgs) {
		append(&kept_tail, msgs[i])
	}
	for i in start ..< drop_end {
		provider.destroy_message(msgs[i])
	}
	clear(msgs)
	for m in kept_sys {
		append(msgs, m)
	}
	append(msgs, provider.Message{
		role = .User,
		content = fmt.aprintf("Conversation summary (auto-compacted):\n%s", summary),
	})
	delete(summary)
	for m in kept_tail {
		append(msgs, m)
	}
}
