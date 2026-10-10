// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Gemini generateContent response parsing: candidates[].content.parts into
Chat_Response (text, functionCall, thought parts), usageMetadata to usage.
*/

package provider

import "core:encoding/json"
import "core:fmt"
import "core:strings"

@(private)
gemini_json_string :: proc(obj: json.Object, key: string) -> string {
	if v, ok := obj[key]; ok {
		if s, sok := v.(json.String); sok {
			return string(s)
		}
	}
	return ""
}

@(private)
gemini_obj :: proc(obj: json.Object, key: string) -> (json.Object, bool) {
	if v, ok := obj[key]; ok {
		if o, ook := v.(json.Object); ook {
			return o, true
		}
	}
	return nil, false
}

@(private)
gemini_arr :: proc(obj: json.Object, key: string) -> (json.Array, bool) {
	if v, ok := obj[key]; ok {
		if a, aok := v.(json.Array); aok {
			return a, true
		}
	}
	return nil, false
}

parse_gemini_response :: proc(body: string, allocator := context.allocator) -> Chat_Response {
	res: Chat_Response
	doc, perr := json.parse_string(body, .JSON, allocator = context.temp_allocator)
	if perr != .None {
		res.err = fmt.aprintf("bad gemini JSON: %v", perr, allocator = allocator)
		return res
	}
	root, rok := doc.(json.Object)
	if !rok {
		res.err = strings.clone("gemini payload is not an object", allocator)
		return res
	}

	if eobj, eok := gemini_obj(root, "error"); eok {
		if msg := gemini_json_string(eobj, "message"); len(msg) > 0 {
			res.err = strings.clone(msg, allocator)
		} else {
			res.err = strings.clone("gemini error", allocator)
		}
		return res
	}
	if fb, fok := gemini_obj(root, "promptFeedback"); fok {
		if br := gemini_json_string(fb, "blockReason"); len(br) > 0 {
			res.err = fmt.aprintf("gemini blocked the prompt: %s", br, allocator = allocator)
			return res
		}
	}
	res.ok = true

	cands, cok := gemini_arr(root, "candidates")
	if !cok || len(cands) == 0 {
		res.ok = false
		res.err = strings.clone("gemini response has no candidates", allocator)
		return res
	}
	cand, candok := cands[0].(json.Object)
	if !candok {
		res.ok = false
		res.err = strings.clone("gemini candidate is not an object", allocator)
		return res
	}
	res.finish_reason = strings.clone(gemini_json_string(cand, "finishReason"), allocator)

	content: strings.Builder
	strings.builder_init(&content, allocator)
	reasoning: strings.Builder
	strings.builder_init(&reasoning, allocator)
	calls := make([dynamic]Tool_Call, allocator)

	if cobj, cok2 := gemini_obj(cand, "content"); cok2 {
		if parts, pok := gemini_arr(cobj, "parts"); pok {
			call_i := 0
			for part in parts {
				po, ppok := part.(json.Object)
				if !ppok {
					continue
				}
				if fc, fok := gemini_obj(po, "functionCall"); fok {
					name := gemini_json_string(fc, "name")
					// Zen may echo calls namespaced as default_api:name.
					if strings.has_prefix(name, "default_api:") {
						name = name[len("default_api:"):]
					}
					args := ""
					if av, aok := fc["args"]; aok {
						if raw, merr := json.marshal(av, allocator = context.temp_allocator); merr == nil {
							args = string(raw)
						}
					}
					if len(name) == 0 {
						continue
					}
					// thoughtSignature sits beside functionCall on the part and
					// must be echoed verbatim on replay or Gemini 3 400s.
					sig := gemini_json_string(po, "thoughtSignature")
					append(&calls, Tool_Call{
						id = fmt.aprintf("gemini_fc_%d", call_i, allocator = allocator),
						name = strings.clone(name, allocator),
						arguments = strings.clone(args, allocator),
						signature = strings.clone(sig, allocator),
					})
					call_i += 1
					continue
				}
				if t := gemini_json_string(po, "text"); len(t) > 0 {
					// Thought parts carry "thought":true alongside text.
					if th, thok := po["thought"].(json.Boolean); thok && bool(th) {
						strings.write_string(&reasoning, t)
					} else {
						strings.write_string(&content, t)
					}
				}
			}
		}
	}
	res.content = strings.to_string(content)
	res.reasoning = strings.to_string(reasoning)
	res.tool_calls = calls[:]

	if um, uok := gemini_obj(root, "usageMetadata"); uok {
		res.usage.prompt_tokens = json_int_field(um, "promptTokenCount")
		res.usage.completion_tokens = json_int_field(um, "candidatesTokenCount")
		res.usage.total_tokens = json_int_field(um, "totalTokenCount")
		res.usage.reasoning_tokens = json_int_field(um, "thoughtsTokenCount")
		res.usage.cache_read_tokens = json_int_field(um, "cachedContentTokenCount")
		if res.usage.total_tokens == 0 {
			res.usage.total_tokens = res.usage.prompt_tokens + res.usage.completion_tokens
		}
	}

	res.model = strings.clone(gemini_json_string(root, "modelVersion"), allocator)
	return res
}
