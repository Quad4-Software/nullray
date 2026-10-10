// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
OpenAI Responses API response parsing: output items (message, function_call,
reasoning summaries) into Chat_Response, plus usage mapping.
*/

package provider

import "core:encoding/json"
import "core:fmt"
import "core:strings"

@(private)
responses_json_string :: proc(obj: json.Object, key: string) -> string {
	if v, ok := obj[key]; ok {
		if s, sok := v.(json.String); sok {
			return string(s)
		}
	}
	return ""
}

@(private)
responses_obj :: proc(obj: json.Object, key: string) -> (json.Object, bool) {
	if v, ok := obj[key]; ok {
		if o, ook := v.(json.Object); ook {
			return o, true
		}
	}
	return nil, false
}

@(private)
responses_arr :: proc(obj: json.Object, key: string) -> (json.Array, bool) {
	if v, ok := obj[key]; ok {
		if a, aok := v.(json.Array); aok {
			return a, true
		}
	}
	return nil, false
}

// Text of one part list under a message/reasoning output item.
@(private)
responses_parts_text :: proc(b: ^strings.Builder, parts: json.Array, kind: string) {
	for part in parts {
		po, pok := part.(json.Object)
		if !pok {
			continue
		}
		pt := responses_json_string(po, "type")
		// output_text for message content, summary_text for reasoning,
		// refuse/refusal for refusals.
		switch pt {
		case "output_text", "summary_text", "refusal", "refuse":
			if t := responses_json_string(po, "text"); len(t) > 0 {
				strings.write_string(b, t)
			}
		case:
			_ = kind
		}
	}
}

parse_responses_response :: proc(body: string, allocator := context.allocator) -> Chat_Response {
	res: Chat_Response
	doc, perr := json.parse_string(body, .JSON, allocator = context.temp_allocator)
	if perr != .None {
		res.err = fmt.aprintf("bad responses JSON: %v", perr, allocator = allocator)
		return res
	}
	root, rok := doc.(json.Object)
	if !rok {
		res.err = strings.clone("responses payload is not an object", allocator)
		return res
	}

	if eobj, eok := responses_obj(root, "error"); eok {
		if msg := responses_json_string(eobj, "message"); len(msg) > 0 {
			res.err = strings.clone(msg, allocator)
			return res
		}
	}
	if responses_json_string(root, "status") == "failed" {
		res.err = strings.clone("responses status=failed", allocator)
		return res
	}
	res.ok = true

	res.model = strings.clone(responses_json_string(root, "model"), allocator)
	res.finish_reason = strings.clone(responses_json_string(root, "status"), allocator)
	if inc, iok := responses_obj(root, "incomplete_details"); iok {
		if reason := responses_json_string(inc, "reason"); len(reason) > 0 {
			delete(res.finish_reason)
			res.finish_reason = strings.clone(reason, allocator)
		}
	}

	content: strings.Builder
	strings.builder_init(&content, allocator)
	reasoning: strings.Builder
	strings.builder_init(&reasoning, allocator)
	calls := make([dynamic]Tool_Call, allocator)

	if out, ook := responses_arr(root, "output"); ook {
		call_i := 0
		for item in out {
			io, iok := item.(json.Object)
			if !iok {
				continue
			}
			it := responses_json_string(io, "type")
			switch it {
			case "message":
				if parts, pok := responses_arr(io, "content"); pok {
					responses_parts_text(&content, parts, "text")
				}
			case "function_call":
				id := responses_json_string(io, "call_id")
				if len(id) == 0 {
					id = responses_json_string(io, "id")
				}
				if len(id) == 0 {
					id = fmt.aprintf("fc_%d", call_i, allocator = allocator)
				}
				append(&calls, Tool_Call{
					id = strings.clone(id, allocator),
					name = strings.clone(responses_json_string(io, "name"), allocator),
					arguments = strings.clone(responses_json_string(io, "arguments"), allocator),
				})
				call_i += 1
			case "reasoning":
				if parts, pok := responses_arr(io, "summary"); pok {
					responses_parts_text(&reasoning, parts, "reasoning")
				}
			case:
			}
		}
	}
	res.content = strings.to_string(content)
	res.reasoning = strings.to_string(reasoning)
	res.tool_calls = calls[:]

	if uobj, uok := responses_obj(root, "usage"); uok {
		res.usage.prompt_tokens = json_int_field(uobj, "input_tokens")
		res.usage.completion_tokens = json_int_field(uobj, "output_tokens")
		res.usage.total_tokens = json_int_field(uobj, "total_tokens")
		if res.usage.total_tokens == 0 {
			res.usage.total_tokens = res.usage.prompt_tokens + res.usage.completion_tokens
		}
		if det, dok := responses_obj(uobj, "output_tokens_details"); dok {
			res.usage.reasoning_tokens = json_int_field(det, "reasoning_tokens")
		}
		if det, dok := responses_obj(uobj, "input_tokens_details"); dok {
			res.usage.cache_read_tokens = json_int_field(det, "cached_tokens")
		}
	}

	return res
}
