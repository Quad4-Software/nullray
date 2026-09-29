// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Anthropic Messages streaming driver: retry loop around the SSE line handler.
*/

package provider

import "base:runtime"
import "core:strings"
import "core:sync"
import "nullray:constants"
import "nullray:http"

anthropic_chat_stream :: proc(
	p: ^Provider,
	req: Chat_Request,
	on_delta: Delta_Proc,
	user: rawptr,
	allocator := context.allocator,
) -> Chat_Response {
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

		accum: Stream_Accum
		strings.builder_init(&accum.content, allocator)
		strings.builder_init(&accum.reasoning, allocator)
		accum.tool_calls = make([dynamic]Tool_Call, allocator)
		accum.tool_sealed = make([dynamic]bool, allocator)
		accum.block_tool = make([dynamic]int, allocator)
		accum.on_delta = on_delta
		accum.on_tool_seal = req.on_tool_seal
		accum.user = user
		accum.seal_user = req.seal_user
		accum.ok = true

		body := build_anthropic_body(p, req, model, true)
		last = http.post_json_stream(url, headers[:], body, anthropic_sse_line_cb, &accum, constants.HTTP_TIMEOUT_SEC)
		if last.ok {
			if len(accum.err) > 0 {
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
			delete(accum.block_tool)
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
