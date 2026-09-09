// SPDX-License-Identifier: 0BSD

package provider

import "core:encoding/json"
import "core:fmt"
import "core:strings"

@(private)
quirk_new_call_id :: proc(prefix: string, idx: int, allocator := context.allocator) -> string {
	return fmt.aprintf("%s_%d", prefix, idx, allocator = allocator)
}

@(private)
quirk_decode_param_value :: proc(raw: string) -> string {
	v := strings.trim_space(raw)
	if len(v) >= 2 && v[0] == '\n' {
		v = strings.trim_space(v[1:])
	}
	if len(v) >= 1 && v[len(v) - 1] == '\n' {
		v = strings.trim_space(v[:len(v) - 1])
	}
	return v
}

@(private)
quirk_find_ci :: proc(hay, needle: string) -> int {
	h := strings.to_lower(hay, context.temp_allocator)
	n := strings.to_lower(needle, context.temp_allocator)
	return strings.index(h, n)
}

@(private)
quirk_parse_qwen_tool_blocks :: proc(
	text: string,
	id_prefix: string,
	allocator := context.allocator,
) -> (
	calls: []Tool_Call,
	cleaned: string,
) {
	if len(text) == 0 || !strings.contains(text, "<tool_call") {
		return nil, strings.clone(text, allocator)
	}
	out := make([dynamic]Tool_Call, allocator)
	kept := strings.builder_make(allocator)
	defer strings.builder_destroy(&kept)
	pos := 0
	call_idx := 0
	for pos < len(text) {
		start := quirk_find_ci(text[pos:], "<tool_call")
		if start < 0 {
			strings.write_string(&kept, text[pos:])
			break
		}
		start += pos
		strings.write_string(&kept, text[pos:start])
		end_tag := quirk_find_ci(text[start:], "</tool_call>")
		block_end := len(text)
		if end_tag >= 0 {
			block_end = start + end_tag + len("</tool_call>")
		}
		block := text[start:block_end]
		func_start := quirk_find_ci(block, "<function=")
		if func_start >= 0 {
			func_start += len("<function=")
			func_end := strings.index_byte(block[func_start:], '>')
			if func_end >= 0 {
				name := strings.trim_space(block[func_start:func_start + func_end])
				body := block[func_start + func_end + 1:]
				args_obj := make(json.Object, context.temp_allocator)
				param_pos := 0
				for param_pos < len(body) {
					pstart := quirk_find_ci(body[param_pos:], "<parameter=")
					if pstart < 0 {
						break
					}
					pstart += param_pos + len("<parameter=")
					pend := strings.index_byte(body[pstart:], '>')
					if pend < 0 {
						break
					}
					key := strings.trim_space(body[pstart:pstart + pend])
					val_start := pstart + pend + 1
					val_end := len(body)
					nstart := quirk_find_ci(body[val_start:], "<parameter=")
					nclose := quirk_find_ci(body[val_start:], "</parameter>")
					if nclose >= 0 && (nstart < 0 || nclose < nstart) {
						val_end = val_start + nclose
					} else if nstart >= 0 {
						val_end = val_start + nstart
					}
					val := quirk_decode_param_value(body[val_start:val_end])
					args_obj[key] = json.Value(val)
					if nclose >= 0 && (nstart < 0 || nclose < nstart) {
						param_pos = val_start + nclose + len("</parameter>")
					} else if nstart >= 0 {
						param_pos = val_start + nstart
					} else {
						break
					}
				}
				args_bytes, jerr := json.marshal(args_obj, allocator = context.temp_allocator)
				args := "{}"
				if jerr == nil {
					args = string(args_bytes)
				}
				if len(name) > 0 {
					append(
						&out,
						Tool_Call{
							id = quirk_new_call_id(id_prefix, call_idx, allocator),
							name = strings.clone(name, allocator),
							arguments = strings.clone(args, allocator),
						},
					)
					call_idx += 1
				}
			}
		}
		pos = block_end
	}
	cleaned = strings.clone(strings.trim_space(strings.to_string(kept)), allocator)
	if len(out) == 0 {
		delete(cleaned)
		return nil, strings.clone(text, allocator)
	}
	return out[:], cleaned
}

@(private)
quirk_apply_tool_xml_in_reasoning :: proc(res: ^Chat_Response, allocator := context.allocator) {
	if len(res.tool_calls) > 0 || len(res.reasoning) == 0 {
		return
	}
	calls, cleaned := quirk_parse_qwen_tool_blocks(res.reasoning, "qwen_xml", allocator)
	if len(calls) == 0 {
		delete(cleaned)
		return
	}
	res.tool_calls = calls
	delete(res.reasoning)
	res.reasoning = cleaned
}

@(private)
quirk_tool_calls_from_json_value :: proc(
	v: json.Value,
	prefix: string,
	allocator := context.allocator,
) -> []Tool_Call {
	arr: json.Array
	#partial switch val in v {
	case json.Array:
		arr = val
	case json.Object:
		if tc, ok := val["tool_calls"]; ok {
			if a, aok := tc.(json.Array); aok {
				arr = a
			}
		}
	}
	if len(arr) == 0 {
		return nil
	}
	out := make([dynamic]Tool_Call, allocator)
	for item, i in arr {
		obj, ok := item.(json.Object)
		if !ok {
			continue
		}
		tc: Tool_Call
		if idv, iok := obj["id"]; iok {
			if s, sok := idv.(json.String); sok {
				tc.id = strings.clone(string(s), allocator)
			}
		}
		name := ""
		args := ""
		if fnv, fok := obj["function"]; fok {
			if fn, fnok := fnv.(json.Object); fnok {
				if nv, nok := fn["name"]; nok {
					if s, sok := nv.(json.String); sok {
						name = string(s)
					}
				}
				if av, aok := fn["arguments"]; aok {
					#partial switch arg in av {
					case json.String:
						args = string(arg)
					case json.Object, json.Array:
						b, err := json.marshal(av, allocator = context.temp_allocator)
						if err == nil {
							args = string(b)
						}
					}
				}
			}
		}
		if len(name) == 0 {
			if nv, nok := obj["name"]; nok {
				if s, sok := nv.(json.String); sok {
					name = string(s)
				}
			}
		}
		if len(args) == 0 {
			if av, aok := obj["arguments"]; aok {
				#partial switch arg in av {
				case json.String:
					args = string(arg)
				case json.Object, json.Array:
					b, err := json.marshal(av, allocator = context.temp_allocator)
					if err == nil {
						args = string(b)
					}
				}
			}
		}
		if len(name) == 0 {
			delete(tc.id)
			continue
		}
		if len(tc.id) == 0 {
			tc.id = quirk_new_call_id(prefix, i, allocator)
		}
		tc.name = strings.clone(name, allocator)
		tc.arguments = strings.clone(args, allocator)
		append(&out, tc)
	}
	if len(out) == 0 {
		return nil
	}
	return out[:]
}

@(private)
quirk_json_candidate :: proc(content: string) -> string {
	trimmed := strings.trim_space(content)
	if len(trimmed) == 0 {
		return ""
	}
	if trimmed[0] == '{' || trimmed[0] == '[' {
		return trimmed
	}
	marker := "```json"
	idx := strings.index(strings.to_lower(trimmed, context.temp_allocator), marker)
	if idx < 0 {
		marker = "```"
		idx = strings.index(trimmed, marker)
	}
	if idx < 0 {
		return ""
	}
	start := idx + len(marker)
	end := strings.index(trimmed[start:], "```")
	if end < 0 {
		return strings.trim_space(trimmed[start:])
	}
	return strings.trim_space(trimmed[start:start + end])
}

@(private)
quirk_apply_tool_json_in_content :: proc(res: ^Chat_Response, allocator := context.allocator) {
	if len(res.tool_calls) > 0 || len(res.content) == 0 {
		return
	}
	candidate := quirk_json_candidate(res.content)
	if len(candidate) == 0 {
		return
	}
	doc, err := json.parse_string(candidate, .JSON, allocator = context.temp_allocator)
	if err != .None {
		return
	}
	calls := quirk_tool_calls_from_json_value(doc, "json_content", allocator)
	if len(calls) == 0 {
		return
	}
	res.tool_calls = calls
}

@(private)
quirk_reasoning_useful_text :: proc(reasoning: string, allocator := context.allocator) -> string {
	calls, cleaned := quirk_parse_qwen_tool_blocks(reasoning, "stall", allocator)
	defer destroy_tool_calls(calls)
	defer delete(cleaned)
	text := strings.trim_space(cleaned)
	if len(text) == 0 {
		text = strings.trim_space(reasoning)
	}
	return strings.clone(text, allocator)
}

@(private)
quirk_apply_reasoning_only_stall :: proc(res: ^Chat_Response, allocator := context.allocator) {
	if len(res.content) > 0 || len(res.tool_calls) > 0 || len(res.reasoning) == 0 {
		return
	}
	useful := quirk_reasoning_useful_text(res.reasoning, allocator)
	if len(useful) == 0 {
		delete(useful)
		return
	}
	res.content = useful
}
