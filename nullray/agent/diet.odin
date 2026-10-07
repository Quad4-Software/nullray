// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Deterministic per-request message diet (AgentDiet, arxiv 2509.23586). Runs on
a cloned list at request build time so real session history is never mutated.
Stubs replace tool result content in place: position, role, name, and
tool_call_id stay intact so provider tool-call pairing stays legal.
*/

package agent

import "core:fmt"
import "core:os"
import "core:strings"
import "nullray:constants"
import "nullray:provider"

DIET_STUB_PREFIX :: "[diet:"
DIET_ELIDED_MARK :: "[diet: elided"

DIET_STALE_AGE :: 8     // a tool result is stale once this many tool results follow it
DIET_TAIL_MSGS :: 6     // lookback window for path or name references
DIET_LONG_CHARS :: 1500 // minimum body size for stale truncation
DIET_HEAD_CHARS :: 400
DIET_TAIL_CHARS :: 200

Diet_Stats :: struct {
	stubbed:      int,
	truncated:    int,
	diet_saved:   int,
	chars_before: int,
	chars_after:  int,
	corvus:       Corvus_Stats,
}

Diet_Replacement :: struct {
	idx:    int,
	text:   string,
	corvus: bool,
}

// NULLRAY_DIET=0 disables. Default on.
diet_enabled :: proc() -> bool {
	if v, ok := os.lookup_env(constants.ENV_DIET, context.temp_allocator); ok {
		switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
		case "0", "false", "no", "off":
			return false
		}
	}
	return true
}

diet_is_file_tool :: proc(name: string) -> bool {
	switch name {
	case "read_file", "write_file", "edit_file", "apply_edits", "multi_edit":
		return true
	}
	return false
}

diet_is_shell_tool :: proc(name: string) -> bool {
	return name == "run_shell" || name == "run_script"
}

diet_is_todo_tool :: proc(name: string) -> bool {
	switch name {
	case "todo_write", "todo_update", "todo_add", "todo_list":
		return true
	}
	return false
}

diet_arg_key :: proc(name: string) -> string {
	switch name {
	case "run_shell", "run_script", "verify":
		return "command"
	case "grep_files", "glob_files":
		return "pattern"
	case "fetch_url":
		return "url"
	case "web_search", "rag_query", "memory_search", "search_tools":
		return "query"
	case "load_skill", "read_artifact", "grep_artifact":
		return "id"
	}
	return "path"
}

// Lightweight string arg extraction. Returns a slice of args_json, no alloc.
diet_arg_value :: proc(args_json, key: string) -> string {
	needle := fmt.tprintf(`"%s"`, key)
	idx := strings.index(args_json, needle)
	if idx < 0 {
		return ""
	}
	rest := args_json[idx + len(needle):]
	colon := strings.index_byte(rest, ':')
	if colon < 0 {
		return ""
	}
	rest = strings.trim_left_space(rest[colon + 1:])
	if len(rest) == 0 || rest[0] != '"' {
		return ""
	}
	rest = rest[1:]
	end := strings.index_byte(rest, '"')
	if end < 0 {
		return ""
	}
	val := rest[:end]
	if len(val) > 160 {
		val = val[:160]
	}
	return val
}

// Resolve a tool result message back to the call that produced it.
diet_call_info :: proc(
	m: provider.Message,
	call_map: map[string]provider.Tool_Call,
) -> (name: string, args: string) {
	name = m.name
	args = ""
	if len(m.tool_call_id) > 0 {
		if c, ok := call_map[m.tool_call_id]; ok {
			name = c.name
			args = c.arguments
		}
	}
	return
}

diet_target :: proc(name, args: string) -> string {
	return diet_arg_value(args, diet_arg_key(name))
}

diet_referenced :: proc(name, target, ref: string) -> bool {
	if len(target) > 0 && strings.contains(ref, target) {
		return true
	}
	if len(name) > 0 && strings.contains(ref, name) {
		return true
	}
	return false
}

diet_stub_text :: proc(name, target, why: string, allocator := context.temp_allocator) -> string {
	label := name
	if len(label) == 0 {
		label = "tool"
	}
	if len(target) > 0 {
		return fmt.aprintf(
			"%s %s %s %s]",
			DIET_STUB_PREFIX,
			label,
			envelope_sanitize_field(target),
			why,
			allocator = allocator,
		)
	}
	return fmt.aprintf("%s %s %s]", DIET_STUB_PREFIX, label, why, allocator = allocator)
}

diet_truncate_text :: proc(content: string, allocator := context.temp_allocator) -> string {
	head := DIET_HEAD_CHARS
	if head > len(content) {
		head = len(content)
	}
	tail_n := DIET_TAIL_CHARS
	if head + tail_n > len(content) {
		tail_n = len(content) - head
	}
	elided := len(content) - head - tail_n
	return fmt.aprintf(
		"%s\n%s %d bytes]\n%s",
		content[:head],
		DIET_ELIDED_MARK,
		elided,
		content[len(content) - tail_n:],
		allocator = allocator,
	)
}

// Every tool_call_id on a tool message must be declared by an earlier
// assistant message. Diet never reorders, so this should always hold on
// already-valid input, checked anyway so callers can fall back safely.
diet_pairing_ok :: proc(msgs: []provider.Message) -> bool {
	declared := make(map[string]int, context.temp_allocator)
	for m, i in msgs {
		if m.role == .Assistant {
			for c in m.tool_calls {
				if len(c.id) > 0 {
					declared[c.id] = i
				}
			}
		}
		if m.role == .Tool && len(m.tool_call_id) > 0 {
			src, ok := declared[m.tool_call_id]
			if !ok || src >= i {
				return false
			}
		}
	}
	return true
}

// Provider rejections that look like a message-shape problem, not transport.
diet_err_looks_shape :: proc(err: string) -> bool {
	lower := strings.to_lower(err, context.temp_allocator)
	needles := []string{"tool_call", "tool call", "tool_use", "tool_result", "tool result", "role", "messages"}
	for nd in needles {
		if strings.contains(lower, nd) {
			return true
		}
	}
	return false
}

// Clone msgs and apply the diet plus the CORVUS file-state pass. Empty
// result means nothing to prune and no state block to inject.
diet_messages :: proc(msgs: []provider.Message, allocator := context.allocator) -> ([dynamic]provider.Message, Diet_Stats) {
	stats := Diet_Stats{chars_before = messages_content_chars(msgs)}
	repl, state := diet_plan(msgs, &stats)
	if len(repl) == 0 && len(state) == 0 {
		stats.chars_after = stats.chars_before
		return make([dynamic]provider.Message, 0, 0, allocator), stats
	}
	out := clone_messages(msgs, allocator)
	for r in repl {
		saved := len(out[r.idx].content) - len(r.text)
		if r.corvus {
			stats.corvus.saved_chars += saved
		} else {
			stats.diet_saved += saved
		}
		delete(out[r.idx].content)
		out[r.idx].content = strings.clone(r.text, allocator)
	}
	if len(state) > 0 && len(out) > 0 {
		last := len(out) - 1
		next := strings.concatenate({out[last].content, state}, allocator)
		delete(out[last].content)
		out[last].content = next
	}
	stats.chars_after = messages_content_chars(out[:])
	return out, stats
}
