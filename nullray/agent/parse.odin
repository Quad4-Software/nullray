// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Plain-text TOOL line fallback parser.
*/

package agent

import "core:encoding/json"
import "core:fmt"
import "core:strings"
import "nullray:provider"

parse_tool_calls_text :: proc(content: string, allocator := context.allocator) -> []provider.Tool_Call {
	lines := strings.split_lines(content, context.temp_allocator)
	out := make([dynamic]provider.Tool_Call, allocator)
	idx := 0
	for line in lines {
		trimmed := strings.trim_space(line)
		if strings.has_prefix(trimmed, "{") {
			// Small models sometimes emit OpenAI-ish JSON objects as bare
			// text: {"name": "x", "arguments": {...}} or {"function": ...}.
			if name, args, ok := parse_json_call_line(trimmed); ok {
				append(&out, provider.Tool_Call{
					id = fmt.aprintf("text_%d", idx, allocator = allocator),
					name = strings.clone(name, allocator),
					arguments = strings.clone(args, allocator),
				})
				idx += 1
			}
			continue
		}
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

// Recognize a bare JSON tool-call object on one line. Returns the tool name
// and args re-encoded as canonical JSON (also repairs malformed arg values:
// non-object args become {"_raw": value}).
@(private)
parse_json_call_line :: proc(line: string) -> (name, args: string, ok: bool) {
	obj, perr := json.parse_string(line, .JSON, allocator = context.temp_allocator)
	if perr != .None {
		return "", "", false
	}
	o, is_obj := obj.(json.Object)
	if !is_obj {
		return "", "", false
	}
	NAME_KEYS := []string{"name", "function", "tool"}
	for key in NAME_KEYS {
		if s, is_s := o[key].(json.String); is_s && len(s) > 0 {
			name = s
			break
		}
	}
	// {"function": "name", "arguments": "{...}"} also nests under "tool_call"
	if len(name) == 0 {
		if inner, is_o := o["tool_call"].(json.Object); is_o {
			o = inner
			for key in NAME_KEYS {
				if s, is_s := o[key].(json.String); is_s && len(s) > 0 {
					name = s
					break
				}
			}
		}
	}
	if len(name) == 0 || name == "tool_call" {
		return "", "", false
	}
	raw_args, has_args := o["arguments"]
	if !has_args {
		raw_args, has_args = o["parameters"]
	}
	if !has_args {
		raw_args, has_args = o["args"]
	}
	if !has_args {
		return "", "", false
	}
	#partial switch v in raw_args {
	case json.String:
		// Arguments may themselves be a JSON-encoded string.
		inner, ierr := json.parse_string(v, .JSON, allocator = context.temp_allocator)
		if ierr == .None {
			if _, is_obj2 := inner.(json.Object); is_obj2 {
				args = v
			}
		}
		if len(args) == 0 {
			args = fmt.aprintf(`{{"_raw":%q}}`, v, allocator = context.temp_allocator)
		}
	case json.Object:
		args, _ = json.unparse(v, allocator = context.temp_allocator)
	case:
		args, _ = json.unparse(v, allocator = context.temp_allocator)
		if len(args) == 0 {
			args = `{}`
		} else {
			args = fmt.aprintf(`{{"_raw":%s}}`, args, allocator = context.temp_allocator)
		}
	}
	if len(args) == 0 {
		args = `{}`
	}
	return name, args, true
}


