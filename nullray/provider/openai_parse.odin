// SPDX-License-Identifier: 0BSD
/*
OpenAI-compatible response and models parsing.
*/

package provider

import "core:encoding/json"
import "core:fmt"
import "core:strings"

@(private)
parse_openai_chat_response :: proc(body: string, allocator := context.allocator) -> Chat_Response {
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
	choices, cok := obj["choices"]
	if !cok {
		return Chat_Response{ok = false, err = strings.clone("no choices in response", allocator)}
	}
	arr, aok := choices.(json.Array)
	if !aok || len(arr) == 0 {
		return Chat_Response{ok = false, err = strings.clone("empty choices", allocator)}
	}
	choice, chok := arr[0].(json.Object)
	if !chok {
		return Chat_Response{ok = false, err = strings.clone("bad choice", allocator)}
	}
	if fr, fok := choice["finish_reason"]; fok {
		if s, sok := fr.(json.String); sok {
			out.finish_reason = strings.clone(string(s), allocator)
		}
	}
	msg, mok := choice["message"]
	if !mok {
		return Chat_Response{ok = false, err = strings.clone("no message", allocator)}
	}
	msg_obj, mok2 := msg.(json.Object)
	if !mok2 {
		return Chat_Response{ok = false, err = strings.clone("bad message", allocator)}
	}
	if cval, cok2 := msg_obj["content"]; cok2 {
		if s, sok := cval.(json.String); sok {
			out.content = strings.clone(string(s), allocator)
		} else if _, is_null := cval.(json.Null); is_null {
			out.content = strings.clone("", allocator)
		}
	}
	if rv, rok := msg_obj["reasoning"]; rok {
		if s, sok := rv.(json.String); sok {
			out.reasoning = strings.clone(string(s), allocator)
		}
	}
	if len(out.reasoning) == 0 {
		if rcv, rcok := msg_obj["reasoning_content"]; rcok {
			if s, sok := rcv.(json.String); sok {
				out.reasoning = strings.clone(string(s), allocator)
			}
		}
	}
	if len(out.reasoning) == 0 {
		if tv, tok := msg_obj["thinking"]; tok {
			if s, sok := tv.(json.String); sok {
				out.reasoning = strings.clone(string(s), allocator)
			}
		}
	}
	if len(out.reasoning) == 0 {
		if rdv, rdok := msg_obj["reasoning_details"]; rdok {
			out.reasoning = strings.clone(extract_reasoning_details(rdv), allocator)
		}
	}
	if tcv, tok := msg_obj["tool_calls"]; tok {
		if tc_arr, taok := tcv.(json.Array); taok && len(tc_arr) > 0 {
			calls := make([dynamic]Tool_Call, allocator)
			for item in tc_arr {
				tc_obj, to_ok := item.(json.Object)
				if !to_ok {
					continue
				}
				tc: Tool_Call
				if idv, iok := tc_obj["id"]; iok {
					if s, sok := idv.(json.String); sok {
						tc.id = strings.clone(string(s), allocator)
					}
				}
				if fnv, fok := tc_obj["function"]; fok {
					if fn, fnok := fnv.(json.Object); fnok {
						if nv, nok := fn["name"]; nok {
							if s, sok := nv.(json.String); sok {
								tc.name = strings.clone(string(s), allocator)
							}
						}
						if av, aok := fn["arguments"]; aok {
							if s, sok := av.(json.String); sok {
								tc.arguments = strings.clone(string(s), allocator)
							}
						}
					}
				}
				if len(tc.name) > 0 {
					if len(tc.id) == 0 {
						tc.id = fmt.aprintf("call_%d", len(calls), allocator = allocator)
					}
					append(&calls, tc)
				} else {
					delete(tc.id)
					delete(tc.name)
					delete(tc.arguments)
				}
			}
			out.tool_calls = calls[:]
		}
	}
	if uv, uok := obj["usage"]; uok {
		out.usage = parse_usage_value(uv)
	}
	if !out.ok {
		return out
	}
	if len(out.content) == 0 && len(out.reasoning) == 0 && len(out.tool_calls) == 0 {
		return Chat_Response{ok = false, err = strings.clone("empty model response (unavailable or exhausted)", allocator)}
	}
	return out
}

extract_reasoning_details :: proc(v: json.Value) -> string {
	arr, ok := v.(json.Array)
	if !ok {
		return ""
	}
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	for item, i in arr {
		obj, ook := item.(json.Object)
		if !ook {
			continue
		}
		text := ""
		if tv, tok := obj["text"]; tok {
			if s, sok := tv.(json.String); sok {
				text = string(s)
			}
		}
		if len(text) == 0 {
			if cv, cok := obj["content"]; cok {
				if s, sok := cv.(json.String); sok {
					text = string(s)
				}
			}
		}
		if len(text) == 0 {
			continue
		}
		if i > 0 && strings.builder_len(b) > 0 {
			strings.write_string(&b, "\n")
		}
		strings.write_string(&b, text)
	}
	return strings.to_string(b)
}

parse_usage_value :: proc(v: json.Value) -> Usage {
	obj, ok := v.(json.Object)
	if !ok {
		return {}
	}
	u: Usage
	u.prompt_tokens = json_int_field(obj, "prompt_tokens")
	if u.prompt_tokens == 0 {
		u.prompt_tokens = json_int_field(obj, "input_tokens")
	}
	u.completion_tokens = json_int_field(obj, "completion_tokens")
	if u.completion_tokens == 0 {
		u.completion_tokens = json_int_field(obj, "output_tokens")
	}
	u.total_tokens = json_int_field(obj, "total_tokens")
	if u.total_tokens == 0 {
		u.total_tokens = u.prompt_tokens + u.completion_tokens
	}
	if details_v, dok := obj["completion_tokens_details"]; dok {
		if details, ok2 := details_v.(json.Object); ok2 {
			u.reasoning_tokens = json_int_field(details, "reasoning_tokens")
		}
	}
	if cost, cok := json_float_field_ok(obj, "cost"); cok {
		u.cost_usd = cost
		u.cost_known = true
	} else if cost, cok := json_float_field_ok(obj, "total_cost"); cok {
		u.cost_usd = cost
		u.cost_known = true
	}
	return u
}

@(private)
json_float_field_ok :: proc(obj: json.Object, key: string) -> (f64, bool) {
	v, ok := obj[key]
	if !ok {
		return 0, false
	}
	#partial switch n in v {
	case json.Float:
		return f64(n), true
	case json.Integer:
		return f64(n), true
	}
	return 0, false
}

@(private)
json_int_field :: proc(obj: json.Object, key: string) -> int {
	v, ok := obj[key]
	if !ok {
		return 0
	}
	#partial switch n in v {
	case json.Integer:
		return int(n)
	case json.Float:
		return int(n)
	}
	return 0
}

@(private)
parse_openai_models_body :: proc(body: string, allocator := context.allocator) -> (models: []Model_Info, err: string) {
	doc, parse_err := json.parse_string(body, .JSON, allocator = context.temp_allocator)
	if parse_err != .None {
		return nil, strings.clone("bad models JSON", allocator)
	}
	obj, obj_ok := doc.(json.Object)
	if !obj_ok {
		return nil, strings.clone("unexpected models root", allocator)
	}
	data, dok := obj["data"]
	if !dok {
		return nil, strings.clone("no models data", allocator)
	}
	arr, aok := data.(json.Array)
	if !aok {
		return nil, strings.clone("models data not array", allocator)
	}
	out := make([dynamic]Model_Info, allocator)
	for item in arr {
		mobj, mok := item.(json.Object)
		if !mok {
			continue
		}
		id := ""
		if v, ok := mobj["id"]; ok {
			if s, sok := v.(json.String); sok {
				id = string(s)
			}
		}
		if len(id) == 0 {
			continue
		}
		info := Model_Info{
			id = strings.clone(id, allocator),
			name = strings.clone(id, allocator),
		}
		if rv, rok := mobj["reasoning"]; rok {
			if robj, rook := rv.(json.Object); rook {
				info.has_reasoning_meta = true
				if dv, dok2 := robj["default_effort"]; dok2 {
					if s, sok := dv.(json.String); sok {
						info.reasoning_default = strings.clone(string(s), allocator)
					}
				}
				if dv, dok2 := robj["default_enabled"]; dok2 {
					if b, bok := dv.(json.Boolean); bok {
						info.reasoning_default_on = bool(b)
					}
				}
				if dv, dok2 := robj["mandatory"]; dok2 {
					if b, bok := dv.(json.Boolean); bok {
						info.reasoning_mandatory = bool(b)
					}
				}
				if ev, eok := robj["supported_efforts"]; eok {
					if ear, eaok := ev.(json.Array); eaok {
						effs := make([dynamic]string, allocator)
						for eitem in ear {
							if s, sok := eitem.(json.String); sok {
								append(&effs, strings.clone(string(s), allocator))
							}
						}
						info.reasoning_efforts = effs[:]
					}
				}
			}
		}
		append(&out, info)
	}
	return out[:], ""
}
