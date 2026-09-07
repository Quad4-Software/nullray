// SPDX-License-Identifier: 0BSD
/*
Plain-text TOOL line fallback parser.
*/

package agent

import "core:fmt"
import "core:strings"
import "nullray:provider"

parse_tool_calls_text :: proc(content: string, allocator := context.allocator) -> []provider.Tool_Call {
	lines := strings.split_lines(content, context.temp_allocator)
	out := make([dynamic]provider.Tool_Call, allocator)
	idx := 0
	for line in lines {
		trimmed := strings.trim_space(line)
		if !strings.has_prefix(trimmed, "TOOL ") {
			continue
		}
		rest := trimmed[5:]
		space := strings.index_byte(rest, ' ')
		if space <= 0 {
			continue
		}
		tool_name := strings.trim_space(rest[:space])
		args_part := strings.trim_space(rest[space:])
		if len(tool_name) == 0 || len(args_part) == 0 {
			continue
		}
		if args_part[0] != '{' && args_part[0] != '[' {
			continue
		}
		append(&out, provider.Tool_Call{
			id = fmt.aprintf("text_%d", idx, allocator = allocator),
			name = strings.clone(tool_name, allocator),
			arguments = strings.clone(args_part, allocator),
		})
		idx += 1
	}
	return out[:]
}


