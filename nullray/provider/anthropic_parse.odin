// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Anthropic Messages response parsing: content blocks, tool_use, usage.
*/

package provider

import "core:encoding/json"
import "core:fmt"
import "core:strings"

@(private)
anthropic_usage :: proc(obj: json.Object) -> Usage {
	u := parse_usage_value(obj)
	// Anthropic splits prompt tokens into uncached plus cache buckets.
	u.prompt_tokens += json_int_field(obj, "cache_read_input_tokens")
	u.prompt_tokens += json_int_field(obj, "cache_creation_input_tokens")
	if u.prompt_tokens > 0 || u.completion_tokens > 0 {
		u.total_tokens = u.prompt_tokens + u.completion_tokens
	}
	return u
}

@(private)
parse_anthropic_response :: proc(body: string, allocator := context.allocator) -> Chat_Response {
	doc, parse_err := json.parse_string(body, .JSON, allocator = context.temp_allocator)
	if parse_err != .None {
		return Chat_Response{ok = false, err = strings.clone("bad JSON from provider", allocator)}
	}
	obj, obj_ok := doc.(json.Object)
	if !obj_ok {
		return Chat_Response{ok = false, err = strings.clone("unexpected JSON root", allocator)}
	}
	if err_v, has_err := obj["error"]; has_err {
		if err_obj, ok := err_v.(json.Object); ok {
			if msg, mok := err_obj["message"]; mok {
				if s, sok := msg.(json.String); sok {
					return Chat_Response{ok = false, err = strings.clone(string(s), allocator)}
				}
			}
		}
		return Chat_Response{ok = false, err = strings.clone("provider error", allocator)}
	}

	out: Chat_Response
	out.ok = true
	if m, ok := obj["model"]; ok {
		if s, sok := m.(json.String); sok {
			out.model = strings.clone(string(s), allocator)
		}
	}
	if sr, sok := obj["stop_reason"]; sok {
		if s, ssok := sr.(json.String); ssok {
			out.finish_reason = strings.clone(string(s), allocator)
		}
	}
	content_v, cok := obj["content"]
	carr, caok := content_v.(json.Array)
	if cok && caok {
		text := strings.builder_make(allocator)
		think := strings.builder_make(allocator)
		calls := make([dynamic]Tool_Call, allocator)
		for item in carr {
			bobj, bok := item.(json.Object)
			if !bok {
				continue
			}
			btype := ""
			if tv, tok := bobj["type"]; tok {
				if s, ssok := tv.(json.String); ssok {
					btype = string(s)
				}
			}
			switch btype {
			case "text":
				if tv, tok := bobj["text"]; tok {
					if s, ssok := tv.(json.String); ssok {
						strings.write_string(&text, string(s))
					}
				}
			case "thinking":
				if tv, tok := bobj["thinking"]; tok {
					if s, ssok := tv.(json.String); ssok {
						strings.write_string(&think, string(s))
					}
				}
			case "tool_use":
				tc: Tool_Call
				if iv, iok := bobj["id"]; iok {
					if s, ssok := iv.(json.String); ssok {
						tc.id = strings.clone(string(s), allocator)
					}
				}
				if nv, nok := bobj["name"]; nok {
					if s, ssok := nv.(json.String); ssok {
						tc.name = strings.clone(string(s), allocator)
					}
				}
				if iv, iok := bobj["input"]; iok {
					if raw, merr := json.marshal(iv, allocator = allocator); merr == nil {
						tc.arguments = string(raw)
					}
				}
				if len(tc.name) > 0 {
					if len(tc.id) == 0 {
						tc.id = fmt.aprintf("toolu_%d", len(calls), allocator = allocator)
					}
					append(&calls, tc)
				} else {
					delete(tc.id)
					delete(tc.name)
					delete(tc.arguments)
					delete(tc.signature)
				}
			}
		}
		out.content = strings.to_string(text)
		out.reasoning = strings.to_string(think)
		if len(calls) > 0 {
			out.tool_calls = calls[:]
		} else {
			delete(calls)
		}
	}
	if uv, uok := obj["usage"]; uok {
		if uobj, uook := uv.(json.Object); uook {
			out.usage = anthropic_usage(uobj)
		}
	}
	if len(out.content) == 0 && len(out.reasoning) == 0 && len(out.tool_calls) == 0 {
		return Chat_Response{ok = false, err = strings.clone("empty model response (unavailable or exhausted)", allocator)}
	}
	return out
}
