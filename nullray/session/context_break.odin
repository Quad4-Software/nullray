// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Per-category char counts for /context: system prompt, tools JSON, messages, memory.
Token figures are chars/4 estimates.
*/

package session

import "core:fmt"
import "core:strings"
import "nullray:agent"
import "nullray:provider"
import "nullray:tools"

Context_Break :: struct {
	system_chars:   int,
	tools_chars:    int,
	messages_chars: int,
	memory_chars:   int,
	total_chars:    int,
	budget_chars:   int,
}

context_break_of :: proc(s: ^Session, reg: ^tools.Registry) -> Context_Break {
	out: Context_Break
	if s == nil {
		return out
	}
	out.system_chars = len(s.system_prompt)
	out.budget_chars = agent.compact_chars_budget()
	mode_s := agent.mode_string(s.agent_mode)
	if reg != nil && s.tools_enabled {
		tier := agent.prompt_tier_for_model(s.provider_id, s.model)
		tj := tools.openai_tools_json(reg, mode_s, tier, context.temp_allocator)
		out.tools_chars = len(tj)
	}
	for m in s.messages {
		n := len(m.content) + len(m.reasoning)
		if strings.contains(m.content, "<memory>") || strings.contains(m.content, "skill:") {
			out.memory_chars += n
		} else if m.role != .System {
			out.messages_chars += n
		} else {
			out.system_chars += n
		}
	}
	out.total_chars = out.system_chars + out.tools_chars + out.messages_chars + out.memory_chars
	return out
}

@(private)
est_tokens :: proc(chars: int) -> int {
	return (chars + 3) / 4
}

context_breakdown_text :: proc(s: ^Session, reg: ^tools.Registry, allocator := context.allocator) -> string {
	b := context_break_of(s, reg)
	return fmt.aprintf(
		"context  chars ~tokens\nsystem   %6d  ~%d\ntools    %6d  ~%d\nmessages %6d  ~%d\nmemory   %6d  ~%d\ntotal    %6d  ~%d\nbudget   %6d  last_input=%d",
		b.system_chars, est_tokens(b.system_chars),
		b.tools_chars, est_tokens(b.tools_chars),
		b.messages_chars, est_tokens(b.messages_chars),
		b.memory_chars, est_tokens(b.memory_chars),
		b.total_chars, est_tokens(b.total_chars),
		b.budget_chars,
		s != nil ? s.last_input_chars : 0,
		allocator = allocator,
	)
}
