// SPDX-License-Identifier: 0BSD
/*
Tool-result clearing and clear-then-compact context preparation.
*/

package session

import "nullray:agent"
import "nullray:provider"

compact_chars_from_env :: proc() -> int {
	return agent.compact_chars_budget()
}

tool_clear_keep_from_env :: proc() -> int {
	return agent.tool_clear_keep()
}

messages_content_chars :: proc(msgs: []provider.Message) -> int {
	return agent.messages_content_chars(msgs)
}

is_cleared_tool_content :: proc(content: string) -> bool {
	return agent.is_cleared_tool_content(content)
}

looks_like_tool_error :: proc(content: string) -> bool {
	return agent.looks_like_tool_error(content)
}

tool_clear_stub :: proc(m: provider.Message, allocator := context.allocator) -> string {
	return agent.tool_clear_stub(m, allocator)
}

clear_old_tool_results :: proc(msgs: ^[dynamic]provider.Message, keep: int) -> int {
	return agent.clear_old_tool_results(msgs, keep)
}

/*
Clear-then-compact ladder for a flat message list about to be sent.
Mutates msgs in place. May call the provider for summarization.
*/
session_prepare_context :: proc(msgs: ^[dynamic]provider.Message, p: ^provider.Provider) -> agent.Prepare_Stats {
	return agent.prepare_context(msgs, p)
}
