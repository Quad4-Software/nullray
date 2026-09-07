// SPDX-License-Identifier: 0BSD
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
	if p == nil || len(p.base_url) == 0 {
		return Chat_Response{
			ok = false,
			err = strings.clone("provider base URL missing (set NULLRAY_BASE_URL or OPENAI_BASE_URL)", allocator),
		}
	}
	model := req.model
	if len(model) == 0 {
		model = p.default_model
	}

	headers := make([dynamic]string, context.temp_allocator)
	append_provider_headers(&headers, p)
	url := http.join_url(p.base_url, "/chat/completions")

	ignore := make([dynamic]string, context.temp_allocator)
	retries := http_retry_limit()
	last: http.Response

	for attempt in 0 ..= retries {
		if http.cancel_requested() {
			return Chat_Response{ok = false, err = strings.clone("cancelled", allocator)}
		}
		body := build_openai_chat_body(p, req, model, false, ignore[:])
		last = http.post_json(url, headers[:], body, constants.HTTP_TIMEOUT_SEC, context.temp_allocator)
		if last.ok {
			return parse_openai_chat_response(last.body, allocator)
		}
		if !http_status_retryable(last.status) || attempt >= retries {
			break
		}
		if p.id == "openrouter" {
			for name in extract_openrouter_rate_limit_providers(last.body, context.temp_allocator) {
				append(&ignore, name)
			}
		}
		retry_wait(attempt, last.retry_after)
	}

	err := provider_http_error(last, p, allocator)
	return Chat_Response{ok = false, err = err}
}

build_openai_chat_body :: proc(
	p: ^Provider,
	req: Chat_Request,
	model: string,
	stream: bool,
	ignore: []string,
) -> string {
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	strings.write_string(&b, `{"model":`)
	write_json_string(&b, model)
	strings.write_string(&b, `,"messages":[`)
	for m, i in req.messages {
		if i > 0 {
			strings.write_byte(&b, ',')
		}
		write_message_json(&b, m, p)
	}
	if stream {
		if p != nil && p.id == "cohere" {
			strings.write_string(&b, `],"stream":true`)
		} else {
			strings.write_string(&b, `],"stream":true,"stream_options":{"include_usage":true}`)
		}
	} else {
		strings.write_string(&b, `],"stream":false`)
	}
	write_max_tokens_json(&b, p, req.max_tokens, model)
	write_reasoning_json(&b, p, req.reasoning_effort)
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
	if p != nil && p.id == "openrouter" && cache_enabled() {
		strings.write_string(&b, `,"prompt_cache_key":"nullray"`)
	}
	if p != nil && p.id == "openrouter" {
		write_openrouter_extras(&b, ignore)
	}
	strings.write_byte(&b, '}')
	return strings.to_string(b)
}

openai_list_models :: proc(p: ^Provider, allocator := context.allocator) -> (models: []Model_Info, err: string) {
	if p == nil || len(p.base_url) == 0 {
		return nil, strings.clone("provider base URL missing (set NULLRAY_BASE_URL or OPENAI_BASE_URL)", allocator)
	}
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
		if p.id == "azure" {
			append(headers, fmt.tprintf("api-key: %s", p.api_key))
		} else {
			append(headers, fmt.tprintf("Authorization: Bearer %s", p.api_key))
		}
	}
	if p.id == "openrouter" {
		append(headers, "HTTP-Referer: https://github.com/Quad4-Software/nullray")
		append(headers, fmt.tprintf("X-Title: %s", constants.APP_NAME))
	}
	if p.id == "anthropic" {
		append(headers, "anthropic-version: 2023-06-01")
	}
	if p.id == "openai" || p.id == "openai-compat" || p.id == "azure" {
		if org, ok := os.lookup_env(constants.ENV_OPENAI_ORG, context.temp_allocator); ok && len(org) > 0 {
			append(headers, fmt.tprintf("OpenAI-Organization: %s", org))
		}
		if proj, ok := os.lookup_env(constants.ENV_OPENAI_PROJECT, context.temp_allocator); ok && len(proj) > 0 {
			append(headers, fmt.tprintf("OpenAI-Project: %s", proj))
		}
	}
}

// Official OpenAI and reasoning models prefer max_completion_tokens.
write_max_tokens_json :: proc(b: ^strings.Builder, p: ^Provider, max_tokens: int, model: string) {
	if max_tokens <= 0 {
		return
	}
	if uses_max_completion_tokens(p, model) {
		fmt.sbprintf(b, `,"max_completion_tokens":%d`, max_tokens)
		return
	}
	fmt.sbprintf(b, `,"max_tokens":%d`, max_tokens)
}

uses_max_completion_tokens :: proc(p: ^Provider, model: string) -> bool {
	if p != nil && p.id == "openai" {
		return true
	}
	m := strings.to_lower(model, context.temp_allocator)
	if strings.has_prefix(m, "o1") || strings.has_prefix(m, "o3") || strings.has_prefix(m, "o4") {
		return true
	}
	if strings.has_prefix(m, "gpt-5") {
		return true
	}
	return false
}

write_reasoning_json :: proc(b: ^strings.Builder, p: ^Provider, effort: string) {
	e := strings.trim_space(effort)
	if len(e) == 0 {
		return
	}
	el := strings.to_lower(e, context.temp_allocator)
	id := ""
	if p != nil {
		id = p.id
	}
	switch id {
	case "openrouter":
		strings.write_string(b, `,"reasoning":{"effort":`)
		write_json_string(b, el)
		strings.write_string(b, `}`)
	case "cohere":
		co := "high"
		if el == "none" || el == "minimal" {
			co = "none"
		}
		strings.write_string(b, `,"reasoning_effort":`)
		write_json_string(b, co)
	case "dashscope":
		if el == "none" || el == "minimal" {
			strings.write_string(b, `,"enable_thinking":false`)
		} else {
			strings.write_string(b, `,"enable_thinking":true`)
		}
	case "deepseek":
		if el == "none" {
			strings.write_string(b, `,"thinking":{"type":"disabled"}`)
		} else {
			strings.write_string(b, `,"thinking":{"type":"enabled"},"reasoning_effort":`)
			write_json_string(b, map_deepseek_effort(el))
		}
	case "anthropic":
		return
	case:
		strings.write_string(b, `,"reasoning_effort":`)
		write_json_string(b, el)
	}
}

@(private)
map_deepseek_effort :: proc(el: string) -> string {
	switch el {
	case "minimal", "low":
		return "low"
	case "max":
		return "max"
	case:
		return "high"
	}
}

provider_http_error :: proc(res: http.Response, p: ^Provider = nil, allocator := context.allocator) -> string {
	if res.status == 429 {
		if p != nil && p.id == "openrouter" {
			return openrouter_rate_limit_hint(res.body, allocator)
		}
		if msg := extract_provider_error_message(res.body); len(msg) > 0 {
			return fmt.aprintf("rate limited: %s", msg, allocator = allocator)
		}
		return strings.clone("HTTP 429 rate limited (retry later or lower concurrency)", allocator)
	}
	if msg := extract_provider_error_message(res.body); len(msg) > 0 {
		return strings.clone(msg, allocator)
	}
	if res.status == 401 {
		return strings.clone("HTTP 401 unauthorized (check API key in ~/.config/nullray/env)", allocator)
	}
	if res.status == 402 {
		if p != nil && p.id == "openrouter" {
			return strings.clone("HTTP 402 payment required (OpenRouter credits exhausted)", allocator)
		}
		return strings.clone("HTTP 402 payment required (check billing or credits)", allocator)
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
extract_provider_error_message :: proc(body: string) -> string {
	if len(body) == 0 {
		return ""
	}
	doc, perr := json.parse_string(body, .JSON, allocator = context.temp_allocator)
	if perr != .None {
		return ""
	}
	obj, ok := doc.(json.Object)
	if !ok {
		return ""
	}
	err_v, has := obj["error"]
	if !has {
		return ""
	}
	if err_obj, eok := err_v.(json.Object); eok {
		if msg, mok := err_obj["message"]; mok {
			if s, sok := msg.(json.String); sok {
				return string(s)
			}
		}
	} else if s, sok := err_v.(json.String); sok {
		return string(s)
	}
	return ""
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
write_message_json :: proc(b: ^strings.Builder, m: Message, p: ^Provider = nil) {
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
	if m.role == .Assistant && len(m.reasoning) > 0 {
		field := assistant_reasoning_json_field(p)
		strings.write_string(b, `,"`)
		strings.write_string(b, field)
		strings.write_string(b, `":`)
		write_json_string(b, m.reasoning)
	}
	if m.cacheable && cache_enabled() && message_cache_control_ok(p) {
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
assistant_reasoning_json_field :: proc(p: ^Provider) -> string {
	if p == nil {
		return "reasoning_content"
	}
	switch p.id {
	case "openrouter", "cerebras":
		return "reasoning"
	case:
		return "reasoning_content"
	}
}

@(private)
message_cache_control_ok :: proc(p: ^Provider) -> bool {
	if p == nil {
		return false
	}
	return p.id == "openrouter" || p.id == "anthropic"
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
