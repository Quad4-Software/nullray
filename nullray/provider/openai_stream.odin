// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
OpenAI SSE chat streaming: content, reasoning, and tool_calls deltas.
*/

package provider

import "base:runtime"
import "core:strings"
import "core:sync"
import "nullray:constants"
import "nullray:http"

Stream_Accum :: struct {
	content:      strings.Builder,
	reasoning:    strings.Builder,
	tool_calls:   [dynamic]Tool_Call,
	tool_sealed:  [dynamic]bool,
	finish:       string,
	model:        string,
	err:          string,
	err_status:   int,
	usage:        Usage,
	on_delta:     Delta_Proc,
	on_tool_seal: Tool_Seal_Proc,
	user:         rawptr,
	seal_user:    rawptr,
	mu:           sync.Mutex,
	ok:           bool,
}

openai_chat_stream :: proc(
	p: ^Provider,
	req: Chat_Request,
	on_delta: Delta_Proc,
	user: rawptr,
	allocator := context.allocator,
) -> Chat_Response {
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

	// Per-call temp epoch: request bodies and SSE line scratch allocate on the
	// shared temp arena, which headless mode never frees. Reclaim on return.
	temp_epoch := runtime.default_temp_allocator_temp_begin()
	defer runtime.default_temp_allocator_temp_end(temp_epoch)

	for attempt in 0 ..= retries {
		if http.cancel_requested() {
			return Chat_Response{ok = false, err = strings.clone("cancelled", allocator)}
		}

		accum: Stream_Accum
		strings.builder_init(&accum.content, allocator)
		strings.builder_init(&accum.reasoning, allocator)
		accum.tool_calls = make([dynamic]Tool_Call, allocator)
		accum.tool_sealed = make([dynamic]bool, allocator)
		accum.on_delta = on_delta
		accum.on_tool_seal = req.on_tool_seal
		accum.user = user
		accum.seal_user = req.seal_user
		accum.ok = true

		body := build_openai_chat_body(p, req, model, true, ignore[:])
		last = http.post_json_stream(url, headers[:], body, sse_line_cb, &accum, constants.HTTP_TIMEOUT_SEC)
		if last.ok {
			if len(accum.err) > 0 {
				// SSE error chunk (HTTP 200). Retry transient upstream
				// failures instead of killing the turn.
				retryable := accum.err_status == 0 || http_status_retryable(accum.err_status)
				if retryable && attempt < retries {
					stream_accum_reset(&accum)
					retry_wait(attempt, 0)
					continue
				}
				out_err := strings.clone(accum.err, allocator)
				stream_accum_reset(&accum)
				return Chat_Response{ok = false, err = out_err}
			}

			// Seal remaining tool indices before handing calls to the agent.
			{
				sync.mutex_lock(&accum.mu)
				newly := make([dynamic]int, context.temp_allocator)
				for i in 0 ..< len(accum.tool_calls) {
					for len(accum.tool_sealed) <= i {
						append(&accum.tool_sealed, false)
					}
					if !accum.tool_sealed[i] {
						accum.tool_sealed[i] = true
						append(&newly, i)
					}
				}
				cb := accum.on_tool_seal
				su := accum.seal_user
				sync.mutex_unlock(&accum.mu)
				if cb != nil {
					for i in newly {
						tc := accum.tool_calls[i]
						cb(i, tc.id, tc.name, tc.arguments, su)
					}
				}
			}

			content := strings.clone(strings.to_string(accum.content), allocator)
			reasoning := strings.clone(strings.to_string(accum.reasoning), allocator)
			strings.builder_destroy(&accum.content)
			strings.builder_destroy(&accum.reasoning)
			calls := accum.tool_calls[:]
			delete(accum.tool_sealed)
			if len(content) == 0 && len(reasoning) == 0 && len(calls) == 0 {
				delete(content)
				delete(reasoning)
				destroy_tool_calls(calls)
				delete(accum.tool_calls)
				delete(accum.finish)
				delete(accum.model)
				return Chat_Response{
					ok = false,
					err = strings.clone("empty model response (unavailable or exhausted)", allocator),
				}
			}
			return Chat_Response{
				ok = true,
				content = content,
				reasoning = reasoning,
				model = accum.model,
				tool_calls = calls,
				finish_reason = accum.finish,
				usage = accum.usage,
			}
		}

		stream_accum_reset(&accum)

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
		if len(last.body) > 0 {
			delete(last.body)
			last.body = ""
		}
		retry_wait(attempt, last.retry_after)
	}

	err := provider_http_error(last, p, allocator)
	if len(last.body) > 0 {
		delete(last.body)
	}
	return Chat_Response{ok = false, err = err}
}

