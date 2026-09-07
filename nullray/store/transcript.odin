// SPDX-License-Identifier: 0BSD
/*
JSONL transcript save/load and preview helpers.
*/

package store

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import "nullray:constants"
import "nullray:provider"

save_transcript :: proc(path: string, messages: []provider.Message) -> bool {
	ensure_session_dir()
	f, err := os.open(path, {.Write, .Create, .Trunc}, {.Read_User, .Write_User})
	if err != nil {
		return false
	}
	defer os.close(f)
	for m in messages {
		if m.role == .System {
			continue
		}
		b: strings.Builder
		strings.builder_init(&b, context.temp_allocator)
		strings.write_string(&b, `{"ts":`)
		fmt.sbprint(&b, time.to_unix_seconds(time.now()))
		strings.write_string(&b, `,"role":`)
		strings.write_string(&b, json_quote(provider.role_string(m.role)))
		strings.write_string(&b, `,"content":`)
		strings.write_string(&b, json_quote(m.content))
		if len(m.name) > 0 {
			strings.write_string(&b, `,"name":`)
			strings.write_string(&b, json_quote(m.name))
		}
		if len(m.tool_call_id) > 0 {
			strings.write_string(&b, `,"tool_call_id":`)
			strings.write_string(&b, json_quote(m.tool_call_id))
		}
		if len(m.reasoning) > 0 {
			strings.write_string(&b, `,"reasoning":`)
			strings.write_string(&b, json_quote(m.reasoning))
		}
		if len(m.tool_calls) > 0 {
			strings.write_string(&b, `,"tool_calls":[`)
			for tc, i in m.tool_calls {
				if i > 0 {
					strings.write_byte(&b, ',')
				}
				strings.write_string(&b, `{"id":`)
				strings.write_string(&b, json_quote(tc.id))
				strings.write_string(&b, `,"name":`)
				strings.write_string(&b, json_quote(tc.name))
				strings.write_string(&b, `,"arguments":`)
				strings.write_string(&b, json_quote(tc.arguments))
				strings.write_byte(&b, '}')
			}
			strings.write_byte(&b, ']')
		}
		strings.write_string(&b, "}\n")
		_, werr := os.write_string(f, strings.to_string(b))
		if werr != nil {
			return false
		}
	}
	return true
}

load_transcript :: proc(path: string, allocator := context.allocator) -> (msgs: [dynamic]provider.Message, ok: bool) {
	msgs = make([dynamic]provider.Message, allocator)
	data, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil {
		return msgs, false
	}
	lines := strings.split_lines(string(data), context.temp_allocator)
	for raw in lines {
		line := strings.trim_space(raw)
		if len(line) == 0 {
			continue
		}
		doc, perr := json.parse_string(line, .JSON, allocator = context.temp_allocator)
		if perr != .None {
			continue
		}
		obj, ook := doc.(json.Object)
		if !ook {
			continue
		}
		role_s := ""
		content := ""
		name := ""
		reasoning := ""
		tool_call_id := ""
		if rv, rok := obj["role"]; rok {
			if s, sok := rv.(json.String); sok {
				role_s = string(s)
			}
		}
		if cv, cok := obj["content"]; cok {
			if s, sok := cv.(json.String); sok {
				content = string(s)
			}
		}
		if nv, nok := obj["name"]; nok {
			if s, sok := nv.(json.String); sok {
				name = string(s)
			}
		}
		if rsv, rsok := obj["reasoning"]; rsok {
			if s, sok := rsv.(json.String); sok {
				reasoning = string(s)
			}
		}
		if tid, tok := obj["tool_call_id"]; tok {
			if s, sok := tid.(json.String); sok {
				tool_call_id = string(s)
			}
		}
		role := provider.Role.User
		switch role_s {
		case "assistant":
			role = .Assistant
		case "system":
			continue
		case "tool":
			role = .Tool
		case "user":
			role = .User
		case:
			continue
		}
		if len(content) > constants.MAX_MESSAGE_CHARS {
			content = content[:constants.MAX_MESSAGE_CHARS]
		}
		msg := provider.Message{
			role = role,
			content = strings.clone(content, allocator),
		}
		if len(name) > 0 {
			msg.name = strings.clone(name, allocator)
		}
		if len(reasoning) > 0 {
			msg.reasoning = strings.clone(reasoning, allocator)
		}
		if len(tool_call_id) > 0 {
			msg.tool_call_id = strings.clone(tool_call_id, allocator)
		}
		if tcv, tcok := obj["tool_calls"]; tcok {
			if arr, aok := tcv.(json.Array); aok && len(arr) > 0 {
				calls := make([]provider.Tool_Call, len(arr), allocator)
				for item, i in arr {
					tobj, took := item.(json.Object)
					if !took {
						continue
					}
					id, name_s, args := "", "", ""
					if v, ok := tobj["id"]; ok {
						if s, sok := v.(json.String); sok {
							id = string(s)
						}
					}
					if v, ok := tobj["name"]; ok {
						if s, sok := v.(json.String); sok {
							name_s = string(s)
						}
					}
					if v, ok := tobj["arguments"]; ok {
						if s, sok := v.(json.String); sok {
							args = string(s)
						}
					}
					calls[i] = provider.Tool_Call{
						id = strings.clone(id, allocator),
						name = strings.clone(name_s, allocator),
						arguments = strings.clone(args, allocator),
					}
				}
				msg.tool_calls = calls
			}
		}
		append(&msgs, msg)
	}
	return msgs, true
}

session_body_contains :: proc(path: string, query_lower: string) -> bool {
	data, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil || len(data) == 0 {
		return false
	}
	return strings.contains(strings.to_lower(string(data), context.temp_allocator), query_lower)
}

@(private)
session_group_snippet :: proc(path: string, max_chars: int, allocator := context.allocator) -> string {
	data, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil || len(data) == 0 {
		return ""
	}
	lines := strings.split_lines(string(data), context.temp_allocator)
	b: strings.Builder
	strings.builder_init(&b, allocator)
	// Take from the end for recent context
	start := 0
	if len(lines) > 12 {
		start = len(lines) - 12
	}
	for raw in lines[start:] {
		line := strings.trim_space(raw)
		if len(line) == 0 {
			continue
		}
		doc, perr := json.parse_string(line, .JSON, allocator = context.temp_allocator)
		if perr != .None {
			continue
		}
		obj, ook := doc.(json.Object)
		if !ook {
			continue
		}
		role_s := ""
		content := ""
		if rv, rok := obj["role"]; rok {
			if s, sok := rv.(json.String); sok {
				role_s = string(s)
			}
		}
		if cv, cok := obj["content"]; cok {
			if s, sok := cv.(json.String); sok {
				content = string(s)
			}
		}
		if role_s != "user" && role_s != "assistant" {
			continue
		}
		snip := content
		if len(snip) > 400 {
			snip = snip[:400]
		}
		fmt.sbprintf(&b, "%s: %s\n", role_s, snip)
		if strings.builder_len(b) >= max_chars {
			break
		}
	}
	out := strings.to_string(b)
	if len(out) > max_chars {
		return strings.clone(out[:max_chars], allocator)
	}
	return out
}

@(private)
session_preview :: proc(path: string, allocator := context.allocator) -> string {
	data, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil || len(data) == 0 {
		return strings.clone("(empty)", allocator)
	}
	lines := strings.split_lines(string(data), context.temp_allocator)
	last := ""
	for raw in lines {
		line := strings.trim_space(raw)
		if len(line) == 0 {
			continue
		}
		doc, perr := json.parse_string(line, .JSON, allocator = context.temp_allocator)
		if perr != .None {
			continue
		}
		obj, ook := doc.(json.Object)
		if !ook {
			continue
		}
		role_s := ""
		content := ""
		if rv, rok := obj["role"]; rok {
			if s, sok := rv.(json.String); sok {
				role_s = string(s)
			}
		}
		if cv, cok := obj["content"]; cok {
			if s, sok := cv.(json.String); sok {
				content = string(s)
			}
		}
		if role_s == "user" || role_s == "assistant" {
			snip := content
			if len(snip) > 72 {
				snip = snip[:72]
			}
			last = fmt.tprintf("%s: %s", role_s, snip)
		}
	}
	if len(last) == 0 {
		return strings.clone("(empty)", allocator)
	}
	return strings.clone(last, allocator)
}

@(private)
json_quote :: proc(s: string) -> string {
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	strings.write_byte(&b, '"')
	for r in s {
		switch r {
		case '"':
			strings.write_string(&b, `\"`)
		case '\\':
			strings.write_string(&b, `\\`)
		case '\n':
			strings.write_string(&b, `\n`)
		case '\r':
			strings.write_string(&b, `\r`)
		case '\t':
			strings.write_string(&b, `\t`)
		case:
			if r < 0x20 {
				fmt.sbprintf(&b, `\u%04x`, int(r))
			} else {
				strings.write_rune(&b, r)
			}
		}
	}
	strings.write_byte(&b, '"')
	return strings.to_string(b)
}
