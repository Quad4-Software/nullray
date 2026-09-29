// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Turn inspection helpers for the verify gate: did the turn write files, did it
call tools, a budgeted diff summary, and blocking-finding counts from review
text.
*/

package agent

import "core:fmt"
import "core:strings"
import "nullray:constants"
import "nullray:provider"

turn_had_writes :: proc(messages: []provider.Message) -> bool {
	for m in messages {
		switch m.role {
		case .Assistant:
			for tc in m.tool_calls {
				if tool_name_is_workspace_write(tc.name) {
					return true
				}
			}
		case .Tool:
			if tool_name_is_workspace_write(m.name) {
				return true
			}
		case .User, .System:
		}
	}
	return false
}

tool_name_is_workspace_write :: proc(name: string) -> bool {
	switch name {
	case "write_file", "edit_file", "apply_edits", "scaffold":
		return true
	}
	return false
}

turn_had_tool_calls :: proc(messages: []provider.Message) -> bool {
	for m in messages {
		if m.role != .Assistant {
			continue
		}
		if len(m.tool_calls) > 0 {
			return true
		}
	}
	return false
}

/*
Build a budgeted diff-ish summary from write/edit tool calls in the turn.
*/
collect_turn_diff :: proc(messages: []provider.Message, allocator := context.allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	for m in messages {
		if m.role != .Assistant {
			continue
		}
		for tc in m.tool_calls {
			switch tc.name {
			case "write_file", "edit_file", "apply_edits":
				fmt.sbprintf(&b, "### %s\n%s\n\n", tc.name, tc.arguments)
			}
		}
	}
	text := strings.to_string(b)
	if len(text) == 0 {
		return strings.clone("(no file edits in this turn)", allocator)
	}
	if len(text) > constants.MAX_REVIEW_DIFF_CHARS {
		return strings.clone(text[:constants.MAX_REVIEW_DIFF_CHARS], allocator)
	}
	return strings.clone(text, allocator)
}

parse_block_findings :: proc(review_text: string) -> (blocks: int, total: int) {
	scan := review_text
	if idx := strings.last_index(review_text, "--- hunt oracle ---"); idx >= 0 {
		scan = review_text[idx:]
	}
	lines := strings.split_lines(scan, context.temp_allocator)
	for line in lines {
		trimmed := strings.trim_space(line)
		lower := strings.to_lower(trimmed, context.temp_allocator)
		if strings.has_prefix(lower, "findings:") {
			continue
		}
		if strings.has_prefix(lower, "--- hunt") {
			continue
		}
		sev, _, _, _, ok := parse_finding_line(trimmed)
		if !ok {
			continue
		}
		total += 1
		if finding_is_blocking(sev) {
			blocks += 1
		}
	}
	n, found := parse_findings_trailer(review_text)
	if found && n > total {
		total = n
	}
	return blocks, total
}

finding_is_blocking :: proc(sev: string) -> bool {
	switch strings.to_lower(strings.trim_space(sev), context.temp_allocator) {
	case "block", "critical", "high", "major":
		return true
	}
	return false
}
