// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Anthropic Messages API surface (POST {base}/messages). Used by the anthropic
provider and by OpenCode Zen models routed to /zen/v1/messages.
*/

package provider

import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:strings"
import "nullray:constants"
import "nullray:http"

ANTHROPIC_THINKING_BUDGET_MIN :: 1024

anthropic_chat :: proc(p: ^Provider, req: Chat_Request, allocator := context.allocator) -> Chat_Response {
	if p == nil || len(p.base_url) == 0 {
		return Chat_Response{
			ok = false,
			err = strings.clone("provider base URL missing", allocator),
		}
	}
	model := req.model
	if len(model) == 0 {
		model = p.default_model
	}

	headers := make([dynamic]string, context.temp_allocator)
	anthropic_request_headers(&headers, p, req.session_id)
	url := http.join_url(p.base_url, "/messages")

	retries := http_retry_limit()
	last: http.Response

	temp_epoch := runtime.default_temp_allocator_temp_begin()
	defer runtime.default_temp_allocator_temp_end(temp_epoch)

	for attempt in 0 ..= retries {
		if http.cancel_requested() {
			return Chat_Response{ok = false, err = strings.clone("cancelled", allocator)}
		}
		body := build_anthropic_body(p, req, model, false)
		last = http.post_json(url, headers[:], body, http_timeout_sec(), context.temp_allocator)
		if last.ok {
			return parse_anthropic_response(last.body, allocator)
		}
		if !http_status_retryable(last.status) || attempt >= retries {
			break
		}
		retry_wait(attempt, last.retry_after)
	}

	err := provider_http_error(last, p, allocator)
	return Chat_Response{ok = false, err = err}
}

@(private)
anthropic_version_header :: proc(headers: ^[dynamic]string) {
	for h in headers {
		if strings.has_prefix(h, "anthropic-version:") {
			return
		}
	}
	append(headers, "anthropic-version: 2023-06-01")
}

// The Anthropic Messages surface wants x-api-key auth: Anthropic itself and
// OpenCode Zen /messages both reject Bearer-only requests. OpenCode chat
// completions still use Bearer via append_provider_headers; this path must
// not also add Bearer or Zen receives two auth styles on one request.
@(private)
anthropic_request_headers :: proc(headers: ^[dynamic]string, p: ^Provider, session_id := "") {
	if is_opencode_provider(p) {
		append(headers, "Content-Type: application/json")
		if len(p.api_key) > 0 {
			append(headers, fmt.tprintf("x-api-key: %s", p.api_key))
		}
		append_opencode_headers(headers, p, session_id)
	} else {
		append_provider_headers(headers, p, session_id)
	}
	anthropic_version_header(headers)
}

@(private)
anthropic_thinking_budget :: proc(effort: string) -> int {
	el := strings.to_lower(strings.trim_space(effort), context.temp_allocator)
	switch el {
	case "minimal":
		return 1024
	case "low":
		return 4096
	case "medium":
		return 8192
	case "high":
		return 16384
	case "xhigh":
		return 32768
	case "max":
		return 49152
	}
	return 0
}

@(private)
anthropic_cache_ok :: proc(p: ^Provider) -> bool {
	if p == nil || !cache_enabled() {
		return false
	}
	return p.id == "anthropic" || is_opencode_provider(p)
}

@(private)
write_anthropic_text_block :: proc(b: ^strings.Builder, text: string, cacheable: bool) {
	strings.write_string(b, `{"type":"text","text":`)
	write_json_string(b, text)
	if cacheable {
		strings.write_string(b, `,"cache_control":{"type":"ephemeral"}`)
	}
	strings.write_byte(b, '}')
}

@(private)
write_anthropic_media_blocks :: proc(b: ^strings.Builder, m: Message, wrote_in: bool) -> bool {
	wrote := wrote_in
	for mp in m.media {
		if wrote {
			strings.write_byte(b, ',')
		}
		if mp.kind == .Image {
			strings.write_string(b, `{"type":"image","source":{"type":"base64","media_type":`)
			write_json_string(b, mp.mime)
			strings.write_string(b, `,"data":`)
			write_json_string(b, mp.data_b64)
			strings.write_string(b, `}}`)
		} else {
			kind := mp.kind == .Audio ? "audio" : "video"
			label := mp.label
			if len(label) == 0 {
				label = mp.mime
			}
			write_anthropic_text_block(b, fmt.tprintf("[attached %s: %s]", kind, label), false)
		}
		wrote = true
	}
	return wrote
}

@(private)
write_anthropic_tool_result_block :: proc(b: ^strings.Builder, m: Message) {
	strings.write_string(b, `{"type":"tool_result","tool_use_id":`)
	write_json_string(b, m.tool_call_id)
	if m.is_error {
		strings.write_string(b, `,"is_error":true`)
	}
	strings.write_string(b, `,"content":[{"type":"text","text":`)
	write_json_string(b, m.content)
	strings.write_string(b, `}]}`)
}

/*
Messages must alternate user/assistant and tool results ride inside user
messages. Track the open block and merge consecutive turns into it.
*/
@(private)
write_anthropic_messages :: proc(b: ^strings.Builder, msgs: []Message, p: ^Provider) {
	strings.write_string(b, `,"messages":[`)
	open := false
	cur_user := true
	wrote_block := false
	first := true
	cache_ok := anthropic_cache_ok(p)
	for m in msgs {
		if m.role == .System {
			continue
		}
		as_user := m.role != .Assistant
		if open && cur_user != as_user {
			strings.write_string(b, "]}")
			open = false
		}
		if !open {
			if !first {
				strings.write_byte(b, ',')
			}
			first = false
			strings.write_string(b, `{"role":"`)
			strings.write_string(b, as_user ? "user" : "assistant")
			strings.write_string(b, `","content":[`)
			open = true
			cur_user = as_user
			wrote_block = false
		}
		switch m.role {
		case .User:
			if len(m.content) > 0 || len(m.media) == 0 {
				if wrote_block {
					strings.write_byte(b, ',')
				}
				text := m.content
				if len(text) == 0 {
					text = " "
				}
				write_anthropic_text_block(b, text, m.cacheable && cache_ok)
				wrote_block = true
			}
			wrote_block = write_anthropic_media_blocks(b, m, wrote_block)
		case .Assistant:
			if len(m.content) > 0 || len(m.tool_calls) == 0 {
				if wrote_block {
					strings.write_byte(b, ',')
				}
				text := m.content
				if len(text) == 0 {
					text = " "
				}
				write_anthropic_text_block(b, text, m.cacheable && cache_ok)
				wrote_block = true
			}
			for tc in m.tool_calls {
				if wrote_block {
					strings.write_byte(b, ',')
				}
				wrote_block = true
				strings.write_string(b, `{"type":"tool_use","id":`)
				write_json_string(b, tc.id)
				strings.write_string(b, `,"name":`)
				write_json_string(b, tc.name)
				strings.write_string(b, `,"input":`)
				// Tool_Call.arguments is a JSON object string, so embed raw only
				// when it parses, or the whole request body is poisoned.
				if v, perr := json.parse_string(tc.arguments, .JSON, allocator = context.temp_allocator); perr == .None {
					if _, is_obj := v.(json.Object); is_obj && len(tc.arguments) > 0 {
						strings.write_string(b, tc.arguments)
					} else {
						strings.write_string(b, "{}")
					}
				} else {
					strings.write_string(b, "{}")
				}
				strings.write_byte(b, '}')
			}
		case .Tool:
			if wrote_block {
				strings.write_byte(b, ',')
			}
			wrote_block = true
			write_anthropic_tool_result_block(b, m)
		case .System:
		}
	}
	if open {
		strings.write_string(b, "]}")
	}
	strings.write_byte(b, ']')
}

// Convert OpenAI tools_json ([{"type":"function","function":{...}}]) to the
// Anthropic shape ([{"name","description","input_schema"}]).
@(private)
write_anthropic_tools :: proc(b: ^strings.Builder, tools_json: string) {
	doc, err := json.parse_string(tools_json, .JSON, allocator = context.temp_allocator)
	if err != .None {
		return
	}
	arr, ok := doc.(json.Array)
	if !ok || len(arr) == 0 {
		return
	}
	tb: strings.Builder
	strings.builder_init(&tb, context.temp_allocator)
	defer strings.builder_destroy(&tb)
	wrote := false
	for item in arr {
		obj, ook := item.(json.Object)
		if !ook {
			continue
		}
		fn, fok := obj["function"]
		fobj, fook := fn.(json.Object)
		if !fok || !fook {
			continue
		}
		name := ""
		if nv, nok := fobj["name"]; nok {
			if s, sok := nv.(json.String); sok {
				name = string(s)
			}
		}
		if len(name) == 0 {
			continue
		}
		if wrote {
			strings.write_byte(&tb, ',')
		}
		wrote = true
		strings.write_string(&tb, `{"name":`)
		write_json_string(&tb, name)
		if dv, dok := fobj["description"]; dok {
			if s, sok := dv.(json.String); sok {
				strings.write_string(&tb, `,"description":`)
				write_json_string(&tb, string(s))
			}
		}
		strings.write_string(&tb, `,"input_schema":`)
		if pv, pok := fobj["parameters"]; pok {
			if raw, merr := json.marshal(pv, allocator = context.temp_allocator); merr == nil {
				strings.write_string(&tb, string(raw))
			} else {
				strings.write_string(&tb, `{"type":"object"}`)
			}
		} else {
			strings.write_string(&tb, `{"type":"object"}`)
		}
		strings.write_byte(&tb, '}')
	}
	if wrote {
		strings.write_string(b, `,"tools":[`)
		strings.write_string(b, strings.to_string(tb))
		strings.write_byte(b, ']')
	}
}

@(private)
write_anthropic_tool_choice :: proc(b: ^strings.Builder, choice: string) {
	c := strings.to_lower(strings.trim_space(choice), context.temp_allocator)
	if len(c) == 0 || c == "auto" {
		strings.write_string(b, `,"tool_choice":{"type":"auto"}`)
		return
	}
	switch c {
	case "none":
		strings.write_string(b, `,"tool_choice":{"type":"none"}`)
	case "required", "any":
		strings.write_string(b, `,"tool_choice":{"type":"any"}`)
	case:
		strings.write_string(b, `,"tool_choice":{"type":"tool","name":`)
		write_json_string(b, choice)
		strings.write_byte(b, '}')
	}
}

build_anthropic_body :: proc(p: ^Provider, req: Chat_Request, model: string, stream: bool) -> string {
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	budget := anthropic_thinking_budget(req.reasoning_effort)
	max_tokens := req.max_tokens
	if max_tokens <= 0 {
		max_tokens = constants.DEFAULT_MAX_TOKENS
	}
	if budget > 0 && max_tokens <= budget + ANTHROPIC_THINKING_BUDGET_MIN {
		max_tokens = budget + ANTHROPIC_THINKING_BUDGET_MIN + 1024
	}
	strings.write_string(&b, `{"model":`)
	write_json_string(&b, model)
	fmt.sbprintf(&b, `,"max_tokens":%d`, max_tokens)
	strings.write_string(&b, `,"stream":`)
	strings.write_string(&b, stream ? "true" : "false")

	cache_ok := anthropic_cache_ok(p)
	sys_first := true
	for m in req.messages {
		if m.role != .System || len(m.content) == 0 {
			continue
		}
		if sys_first {
			strings.write_string(&b, `,"system":[`)
			sys_first = false
		} else {
			strings.write_byte(&b, ',')
		}
		write_anthropic_text_block(&b, m.content, m.cacheable && cache_ok)
	}
	if !sys_first {
		strings.write_byte(&b, ']')
	}

	write_anthropic_messages(&b, req.messages, p)

	if len(req.tools_json) > 0 {
		before := strings.builder_len(b)
		write_anthropic_tools(&b, req.tools_json)
		if strings.builder_len(b) > before {
			write_anthropic_tool_choice(&b, req.tool_choice)
		}
	}
	if budget > 0 {
		// Extended thinking rejects temperature/top_p overrides.
		strings.write_string(&b, `,"thinking":{"type":"enabled","budget_tokens":`)
		fmt.sbprintf(&b, "%d}", budget)
	} else {
		if req.temperature_set {
			fmt.sbprintf(&b, `,"temperature":%.4g`, req.temperature)
		}
		if req.top_p_set {
			fmt.sbprintf(&b, `,"top_p":%.4g`, req.top_p)
		}
	}
	strings.write_byte(&b, '}')
	return strings.to_string(b)
}
