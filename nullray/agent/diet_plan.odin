// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Diet planning pass: walks the message list once, computes guards and the
stub or truncation replacements, and returns them without touching input.
*/

package agent

import "core:strings"
import "nullray:provider"

// Compute stub and truncation decisions on the unmodified list. Returned
// texts live in the temp allocator.
diet_plan :: proc(msgs: []provider.Message, stats: ^Diet_Stats) -> [dynamic]Diet_Replacement {
	repl := make([dynamic]Diet_Replacement, context.temp_allocator)
	n := len(msgs)
	if n == 0 {
		return repl
	}
	call_map := make(map[string]provider.Tool_Call, context.temp_allocator)
	protected := make([]bool, n, context.temp_allocator)
	done := make([]bool, n, context.temp_allocator)
	is_tool := make([]bool, n, context.temp_allocator)
	names := make([]string, n, context.temp_allocator)
	targets := make([]string, n, context.temp_allocator)
	last_asst := -1
	first_user := -1
	for m, i in msgs {
		if m.role == .System {
			protected[i] = true
		}
		if m.role == .User && first_user < 0 {
			first_user = i
		}
		if m.role == .Assistant {
			last_asst = i
			for c in m.tool_calls {
				if len(c.id) > 0 {
					call_map[c.id] = c
				}
			}
		}
		if m.role == .Tool {
			is_tool[i] = true
		}
	}
	if first_user >= 0 {
		protected[first_user] = true
	}
	protected[n - 1] = true
	if n >= 2 {
		protected[n - 2] = true
	}

	// Reference window: the tail block plus the last assistant message, so a
	// path the model just named is never pruned even outside the window.
	ref_b: strings.Builder
	strings.builder_init(&ref_b, context.temp_allocator)
	tail_start := n - DIET_TAIL_MSGS
	if tail_start < 0 {
		tail_start = 0
	}
	for i in tail_start ..< n {
		strings.write_string(&ref_b, msgs[i].content)
		strings.write_byte(&ref_b, ' ')
	}
	ref_tail := strings.to_string(ref_b)
	guard_b: strings.Builder
	strings.builder_init(&guard_b, context.temp_allocator)
	strings.write_string(&guard_b, ref_tail)
	if last_asst >= 0 {
		lm := msgs[last_asst]
		strings.write_string(&guard_b, lm.content)
		strings.write_string(&guard_b, lm.reasoning)
		for c in lm.tool_calls {
			strings.write_string(&guard_b, c.arguments)
		}
	}
	ref_guard := strings.to_string(guard_b)

	for m, i in msgs {
		if !is_tool[i] {
			continue
		}
		args: string
		names[i], args = diet_call_info(m, call_map)
		targets[i] = diet_target(names[i], args)
		if diet_is_todo_tool(names[i]) {
			protected[i] = true
		}
		if len(m.tool_call_id) > 0 && last_asst >= 0 {
			for c in msgs[last_asst].tool_calls {
				if c.id == m.tool_call_id {
					protected[i] = true
				}
			}
		}
		if len(targets[i]) >= 4 && strings.contains(ref_guard, targets[i]) {
			protected[i] = true
		}
	}

	// Re-reads and write or patch outcomes for the same path: keep latest.
	// Repeated identical shell commands: keep latest.
	supersede := make(map[string]int, context.temp_allocator)
	for i in 0 ..< n {
		if !is_tool[i] || len(targets[i]) == 0 {
			continue
		}
		key: string
		if diet_is_file_tool(names[i]) {
			key = strings.concatenate({"file:", targets[i]}, context.temp_allocator)
		} else if diet_is_shell_tool(names[i]) {
			key = strings.concatenate({"shell:", targets[i]}, context.temp_allocator)
		}
		if len(key) == 0 {
			continue
		}
		if prev, seen := supersede[key]; seen {
			if !protected[prev] && !done[prev] {
				append(&repl, Diet_Replacement{idx = prev, text = diet_stub_text(names[prev], targets[prev], "superseded, latest kept")})
				done[prev] = true
				stats.stubbed += 1
			}
		}
		supersede[key] = i
	}

	// A web_search whose listed URL was fetched afterwards is expired.
	fetched := make([dynamic]string, context.temp_allocator)
	for m, i in msgs {
		if is_tool[i] && names[i] == "fetch_url" && !m.is_error && len(targets[i]) >= 8 {
			append(&fetched, targets[i])
		}
	}
	for m, i in msgs {
		if !is_tool[i] || names[i] != "web_search" || protected[i] || done[i] {
			continue
		}
		for u in fetched {
			if strings.contains(m.content, u) {
				append(&repl, Diet_Replacement{idx = i, text = diet_stub_text(names[i], targets[i], "superseded by fetch_url")})
				done[i] = true
				stats.stubbed += 1
				break
			}
		}
	}

	// Identical results (same name, args, body): keep the first.
	seen_dup := make(map[string]int, context.temp_allocator)
	for m, i in msgs {
		if !is_tool[i] || protected[i] || done[i] {
			continue
		}
		_, args := diet_call_info(m, call_map)
		key := strings.concatenate({names[i], "\x1f", args, "\x1f", m.content}, context.temp_allocator)
		if _, seen := seen_dup[key]; seen {
			append(&repl, Diet_Replacement{idx = i, text = diet_stub_text(names[i], targets[i], "duplicate result, first kept")})
			done[i] = true
			stats.stubbed += 1
			continue
		}
		seen_dup[key] = i
	}

	// Long stale outputs not referenced in the tail window: head plus tail.
	tool_after := 0
	for i := n - 1; i >= 0; i -= 1 {
		if !is_tool[i] {
			continue
		}
		age := tool_after
		tool_after += 1
		if protected[i] || done[i] {
			continue
		}
		if len(msgs[i].content) <= DIET_LONG_CHARS || age < DIET_STALE_AGE {
			continue
		}
		if diet_referenced(names[i], targets[i], ref_tail) {
			continue
		}
		append(&repl, Diet_Replacement{idx = i, text = diet_truncate_text(msgs[i].content)})
		done[i] = true
		stats.truncated += 1
	}
	return repl
}
