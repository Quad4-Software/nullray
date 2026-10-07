// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
OpenAI-compatible chat completions with native tool_calls.
*/

package provider

import "base:runtime"
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
	if p.id == "openrouter" {
		openrouter_zdr_maybe_warn(p.id)
	}

	headers := make([dynamic]string, context.temp_allocator)
	append_provider_headers(&headers, p, req.session_id)
	url := http.join_url(p.base_url, "/chat/completions")

	ignore := make([dynamic]string, context.temp_allocator)
	retries := http_retry_limit()
	last: http.Response

	// Per-call temp epoch: request bodies allocate on the shared temp arena,
	// which headless mode never frees. Reclaim on return.
	temp_epoch := runtime.default_temp_allocator_temp_begin()
	defer runtime.default_temp_allocator_temp_end(temp_epoch)

	for attempt in 0 ..= retries {
		if http.cancel_requested() {
			return Chat_Response{ok = false, err = strings.clone("cancelled", allocator)}
		}
		sent_constrained := constrained_tools_sent(p, model, req)
		body := build_openai_chat_body(p, req, model, false, ignore[:])
		last = http.post_json(url, headers[:], body, http_timeout_sec_for(p.id), context.temp_allocator)
		if last.ok {
			return parse_openai_chat_response(last.body, allocator)
		}
		// A server that rejects the constraint field once gets it dropped for
		// the session, retry immediately with a clean body.
		if sent_constrained && constrained_rejected(last) {
			constrained_disable(p, last)
			continue
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
	// Per-model profile defaults (model_profiles.json): sampling, reasoning,
	// tool posture. Explicit request fields keep precedence over the profile.
	req_p := req
	pid := ""
	if p != nil {
		pid = p.id
	}
	profile_apply(pid, model, &req_p)
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
	write_max_tokens_json(&b, p, req_p.max_tokens, model)
	write_sampling_json(&b, p, model, req_p.temperature, req_p.top_p, req_p.temperature_set, req_p.top_p_set)
	write_repeat_penalty_json(&b, p, req_p)
	write_reasoning_json(&b, p, req_p.reasoning_effort)
	if p != nil && p.id == "ollama" {
		// Env NULLRAY_OLLAMA_NUM_CTX > profile num_ctx > caps-derived.
		if !write_profile_num_ctx_json(&b, model) {
			write_ollama_num_ctx_json(&b, p, model)
		}
	} else if p != nil && p.id == "llamacpp" {
		// One GET /props per provider instance flags tool support.
		llamacpp_ensure_caps(p)
	}
	if len(req_p.tools_json) > 0 {
		strings.write_string(&b, `,"tools":`)
		strings.write_string(&b, req_p.tools_json)
		choice := req_p.tool_choice
		if len(choice) == 0 {
			choice = "auto"
		}
		strings.write_string(&b, `,"tool_choice":`)
		write_json_string(&b, choice)
		if req_p.parallel_tool_calls_set {
			strings.write_string(&b, `,"parallel_tool_calls":`)
			strings.write_string(&b, req_p.parallel_tool_calls ? "true" : "false")
		}
		// Server-side constrained decoding for local providers, gated by
		// NULLRAY_CONSTRAINED_TOOLS or the profile constrained_tools flag.
		write_constrained_tools_json(&b, p, &req_p, model)
	} else {
		write_response_format_json(&b)
	}
	if p != nil && p.id == "openrouter" && cache_enabled() {
		strings.write_string(&b, `,"prompt_cache_key":"nullray"`)
	}
	if p != nil && p.id == "openrouter" {
		write_openrouter_extras(&b, ignore)
	}
	write_local_cache_hints_json(&b, p)
	strings.write_byte(&b, '}')
	return strings.to_string(b)
}

/*
KV cache and residency hints for local servers. llama.cpp reuses the prompt
KV when cache_prompt is set, so an unchanged prefix skips prefill (warm
starts run far faster than a cold prefill). No id_slot: a fixed slot would
serialize concurrent agents onto one KV slot. Ollama honors a top-level
keep_alive on /v1/chat/completions, so the model stays resident between
turns instead of unloading after the server default.
NULLRAY_OLLAMA_KEEP_ALIVE overrides the 30m duration, 0|off|false|no
disables the field.
*/
write_local_cache_hints_json :: proc(b: ^strings.Builder, p: ^Provider) {
	if p == nil {
		return
	}
	switch p.id {
	case "llamacpp":
		strings.write_string(b, `,"cache_prompt":true`)
	case "ollama":
		keep := ollama_keep_alive(context.temp_allocator)
		if len(keep) > 0 {
			strings.write_string(b, `,"keep_alive":`)
			write_json_string(b, keep)
		}
	case:
	}
}

@(private)
ollama_keep_alive :: proc(allocator := context.allocator) -> string {
	if v, ok := os.lookup_env(constants.ENV_OLLAMA_KEEP_ALIVE, context.temp_allocator); ok {
		raw := strings.trim_space(v)
		switch strings.to_lower(raw, context.temp_allocator) {
		case "0", "off", "false", "no", "disable", "disabled":
			return ""
		}
		return strings.clone(raw, allocator)
	}
	return strings.clone("30m", allocator)
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
	res := http.get_max(
		url,
		headers[:],
		timeout_sec,
		constants.DEFAULT_MODELS_MAX_BYTES,
		context.temp_allocator,
	)
	if !res.ok {
		return nil, strings.clone(res.err, allocator)
	}
	return parse_openai_models_body(res.body, allocator)
}
