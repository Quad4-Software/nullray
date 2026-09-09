// SPDX-License-Identifier: 0BSD
/*
OpenAI-compatible chat completions with native tool_calls.
*/

package provider

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
	if p.id == "openrouter" {
		openrouter_zdr_maybe_warn(p.id)
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
		// Only 429. 502/503 previous_errors can list every upstream, and
		// ignoring them all yields "All providers have been ignored".
		if p.id == "openrouter" && last.status == 429 {
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
	write_sampling_json(&b, p, model, req.temperature, req.top_p, req.temperature_set, req.top_p_set)
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
	return openai_list_models_timeout(p, 30, allocator)
}

openai_list_models_timeout :: proc(
	p: ^Provider,
	timeout_sec: int,
	allocator := context.allocator,
) -> (
	models: []Model_Info,
	err: string,
) {
	if p == nil || len(p.base_url) == 0 {
		return nil, strings.clone("provider base URL missing (set NULLRAY_BASE_URL or OPENAI_BASE_URL)", allocator)
	}
	headers := make([dynamic]string, context.temp_allocator)
	append_provider_headers(&headers, p)
	url := http.join_url(p.base_url, "/models")
	res := http.get(url, headers[:], timeout_sec, context.temp_allocator)
	if !res.ok {
		return nil, strings.clone(res.err, allocator)
	}
	return parse_openai_models_body(res.body, allocator)
}
