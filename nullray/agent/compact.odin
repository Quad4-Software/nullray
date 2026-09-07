// SPDX-License-Identifier: 0BSD
/*
Provider-backed conversation compaction.
*/

package agent

import "core:fmt"
import "core:strings"
import "nullray:provider"

compact_with_model :: proc(p: ^provider.Provider, messages: []provider.Message, allocator := context.allocator) -> (summary: string, ok: bool) {
	if p == nil || p.chat == nil || len(messages) < 4 {
		return "", false
	}
	prompt_b: strings.Builder
	strings.builder_init(&prompt_b, context.temp_allocator)
	strings.write_string(&prompt_b, "Summarize this coding-agent conversation for future context. Keep goals, decisions, file paths, and open tasks. Be concise.\n\n")
	for m in messages {
		if m.role == .System {
			continue
		}
		fmt.sbprintf(&prompt_b, "%s: %s\n\n", provider.role_string(m.role), m.content)
	}
	req_msgs := make([]provider.Message, 1, context.temp_allocator)
	req_msgs[0] = provider.Message{role = .User, content = strings.to_string(prompt_b)}
	req := provider.Chat_Request{
		model = p.default_model,
		messages = req_msgs,
		stream = false,
	}
	res := p.chat(p, req)
	if !res.ok || len(res.content) == 0 {
		provider.destroy_chat_response(&res)
		return "", false
	}
	out := strings.clone(res.content, allocator)
	provider.destroy_chat_response(&res)
	return out, true
}

