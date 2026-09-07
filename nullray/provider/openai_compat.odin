/*
OpenAI-compatible chat completions with native tool_calls.
*/

package provider

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"
import "nullray:constants"
import "nullray:http"

openai_chat :: proc(p: ^Provider, req: Chat_Request, allocator := context.allocator) -> Chat_Response {
	model := req.model
	if len(model) == 0 {
		model = p.default_model
	}

	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	strings.write_string(&b, `{"model":`)
	write_json_string(&b, model)
	strings.write_string(&b, `,"messages":[`)
	for m, i in req.messages {
		if i > 0 {
			strings.write_byte(&b, ',')
		}
		write_message_json(&b, m)
	}
	strings.write_string(&b, `],"stream":false`)
	if req.max_tokens > 0 {
		fmt.sbprintf(&b, `,"max_tokens":%d`, req.max_tokens)
	}
	write_reasoning_json(&b, req.reasoning_effort)
	if len(req.tools_json) > 0 {
		strings.write_string(&b, `,"tools":`)
		strings.write_string(&b, req.tools_json)
		choice := req.tool_choice
		if len(choice) == 0 {
			choice = "auto"
		}
		strings.write_string(&b, `,"tool_choice":`)
		write_json_string(&b, choice)
	}
	if cache_enabled() {
		strings.write_string(&b, `,"prompt_cache_key":"nullray"`)
	}
	strings.write_byte(&b, '}')
	body := strings.to_string(b)

	headers := make([dynamic]string, context.temp_allocator)
	append_provider_headers(&headers, p)

	url := http.join_url(p.base_url, "/chat/completions")
	res := http.post_json(url, headers[:], body, constants.HTTP_TIMEOUT_SEC, context.temp_allocator)
	if !res.ok {
		err := provider_http_error(res, allocator)
		return Chat_Response{ok = false, err = err}
	}

	return parse_openai_chat_response(res.body, allocator)
}

openai_list_models :: proc(p: ^Provider, allocator := context.allocator) -> (models: []Model_Info, err: string) {
	headers := make([dynamic]string, context.temp_allocator)
	append_provider_headers(&headers, p)
	url := http.join_url(p.base_url, "/models")
	res := http.get(url, headers[:], 30, context.temp_allocator)
	if !res.ok {
		return nil, strings.clone(res.err, allocator)
	}
	return parse_openai_models_body(res.body, allocator)
}

append_provider_headers :: proc(headers: ^[dynamic]string, p: ^Provider) {
	append(headers, "Content-Type: application/json")
	if len(p.api_key) > 0 {
		append(headers, fmt.tprintf("Authorization: Bearer %s", p.api_key))
	}
	if p.id == "openrouter" {
		append(headers, "HTTP-Referer: https://github.com/Quad4-Software/nullray")
		append(headers, fmt.tprintf("X-Title: %s", constants.APP_NAME))
	}
}

write_reasoning_json :: proc(b: ^strings.Builder, effort: string) {
	e := strings.trim_space(effort)
	if len(e) == 0 {
		return
	}
	strings.write_string(b, `,"reasoning":{"effort":`)
	write_json_string(b, e)
	strings.write_string(b, `}`)
}

provider_http_error :: proc(res: http.Response, allocator := context.allocator) -> string {
	if len(res.body) > 0 {
		doc, perr := json.parse_string(res.body, .JSON, allocator = context.temp_allocator)
		if perr == .None {
			if obj, ok := doc.(json.Object); ok {
				if err_v, has := obj["error"]; has {
					if err_obj, eok := err_v.(json.Object); eok {
						if msg, mok := err_obj["message"]; mok {
							if s, sok := msg.(json.String); sok {
								return strings.clone(string(s), allocator)
							}
						}
					} else if s, sok := err_v.(json.String); sok {
						return strings.clone(string(s), allocator)
					}
				}
			}
		}
	}
	if res.status == 401 {
		return strings.clone("HTTP 401 unauthorized (check OPENROUTER_API_KEY in ~/.config/nullray/env)", allocator)
	}
	if res.status == 402 {
		return strings.clone("HTTP 402 payment required (OpenRouter credits exhausted)", allocator)
	}
	if res.status == 404 {
		return strings.clone("HTTP 404 model not found or unavailable", allocator)
	}
	if len(res.err) > 0 {
		return strings.clone(res.err, allocator)
	}
	return fmt.aprintf("HTTP %d", res.status, allocator = allocator)
}

@(private)
cache_enabled :: proc() -> bool {
	if v, ok := os.lookup_env(constants.ENV_CACHE, context.temp_allocator); ok {
		switch strings.to_lower(v, context.temp_allocator) {
		case "0", "false", "off", "no":
			return false
		case "1", "true", "on", "yes", "force":
			return true
		}
	}
	if p, ok := os.lookup_env(constants.ENV_PROVIDER, context.temp_allocator); ok {
		pl := strings.to_lower(p, context.temp_allocator)
		if pl == "openrouter" || strings.contains(pl, "anthropic") {
			return true
		}
	}
	return false
}

@(private)
write_message_json :: proc(b: ^strings.Builder, m: Message) {
	strings.write_string(b, `{"role":`)
	write_json_string(b, role_string(m.role))
	if m.role == .Tool {
		if len(m.tool_call_id) > 0 {
			strings.write_string(b, `,"tool_call_id":`)
			write_json_string(b, m.tool_call_id)
		}
		if len(m.name) > 0 {
			strings.write_string(b, `,"name":`)
			write_json_string(b, m.name)
		}
	}
	strings.write_string(b, `,"content":`)
	write_json_string(b, m.content)
	if m.cacheable && cache_enabled() {
		strings.write_string(b, `,"cache_control":{"type":"ephemeral"}`)
	}
	if m.role == .Assistant && len(m.tool_calls) > 0 {
		strings.write_string(b, `,"tool_calls":[`)
		for tc, i in m.tool_calls {
			if i > 0 {
				strings.write_byte(b, ',')
			}
			strings.write_string(b, `{"id":`)
			write_json_string(b, tc.id)
			strings.write_string(b, `,"type":"function","function":{"name":`)
			write_json_string(b, tc.name)
			strings.write_string(b, `,"arguments":`)
			write_json_string(b, tc.arguments)
			strings.write_string(b, `}}`)
		}
		strings.write_byte(b, ']')
	}
	strings.write_byte(b, '}')
}

@(private)
write_json_string :: proc(b: ^strings.Builder, s: string) {
	strings.write_byte(b, '"')
	for r in s {
		switch r {
		case '"':
			strings.write_string(b, `\"`)
		case '\\':
			strings.write_string(b, `\\`)
		case '\n':
			strings.write_string(b, `\n`)
		case '\r':
			strings.write_string(b, `\r`)
		case '\t':
			strings.write_string(b, `\t`)
		case:
			if r < 0x20 {
				fmt.sbprintf(b, `\u%04x`, int(r))
			} else {
				strings.write_rune(b, r)
			}
		}
	}
	strings.write_byte(b, '"')
}

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
	return u
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
		append(&out, Model_Info{id = strings.clone(id, allocator), name = strings.clone(id, allocator)})
	}
	return out[:], ""
}
