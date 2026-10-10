// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
OpenAI Responses API surface (POST {base}/responses). Used by OpenCode Zen
models routed to /zen/v1/responses (gpt-*, grok-*, muse-*).
*/

package provider

import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:strings"
import "nullray:constants"
import "nullray:http"

responses_chat :: proc(p: ^Provider, req: Chat_Request, allocator := context.allocator) -> Chat_Response {
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
	append_provider_headers(&headers, p, req.session_id)
	url := http.join_url(p.base_url, "/responses")

	retries := http_retry_limit()
	last: http.Response

	temp_epoch := runtime.default_temp_allocator_temp_begin()
	defer runtime.default_temp_allocator_temp_end(temp_epoch)

	for attempt in 0 ..= retries {
		if http.cancel_requested() {
			return Chat_Response{ok = false, err = strings.clone("cancelled", allocator)}
		}
		body := build_responses_body(p, req, model)
		last = http.post_json(url, headers[:], body, http_timeout_sec(), context.temp_allocator)
		if last.ok {
			return parse_responses_response(last.body, allocator)
		}
		if !http_status_retryable(last.status) || attempt >= retries {
			break
		}
		retry_wait(attempt, last.retry_after)
	}

	err := provider_http_error(last, p, allocator)
	return Chat_Response{ok = false, err = err}
}

/*
Streaming is folded into one delta: the SSE event vocabulary for Responses
is a separate parser, and a single emitted delta keeps the TUI/print path
correct until that lands.
*/
responses_chat_stream :: proc(
	p: ^Provider,
	req: Chat_Request,
	on_delta: Delta_Proc,
	user: rawptr,
	allocator := context.allocator,
) -> Chat_Response {
	res := responses_chat(p, req, allocator)
	if res.ok && on_delta != nil {
		if len(res.reasoning) > 0 {
			on_delta(.Reasoning, res.reasoning, user)
		}
		if len(res.content) > 0 {
			on_delta(.Content, res.content, user)
		}
	}
	return res
}

/*
Convert chat-completions tools_json ([{"type":"function","function":{...}}])
into the flat Responses shape ({"type":"function","name":...,"parameters":...}).
*/
@(private)
write_responses_tools :: proc(b: ^strings.Builder, tools_json: string) {
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
		obj, is_obj := item.(json.Object)
		if !is_obj {
			continue
		}
		fn_obj := obj
		if fv, fok := obj["function"]; fok {
			if fo, ffok := fv.(json.Object); ffok {
				fn_obj = fo
			}
		}
		name := ""
		if nv, nok := fn_obj["name"]; nok {
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
		strings.write_string(&tb, `{"type":"function","name":`)
		write_json_string(&tb, name)
		if dv, dok := fn_obj["description"]; dok {
			if s, sok := dv.(json.String); sok {
				strings.write_string(&tb, `,"description":`)
				write_json_string(&tb, string(s))
			}
		}
		strings.write_string(&tb, `,"parameters":`)
		if pv, pok := fn_obj["parameters"]; pok {
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

// Joined system text for surfaces that hoist it out of the message list
// (Responses instructions, Gemini systemInstruction).
responses_system_text :: proc(req: Chat_Request, allocator := context.temp_allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	for m in req.messages {
		if m.role != .System {
			continue
		}
		if strings.builder_len(b) > 0 {
			strings.write_byte(&b, '\n')
		}
		strings.write_string(&b, m.content)
	}
	return strings.to_string(b)
}

@(private)
write_responses_input_text :: proc(b: ^strings.Builder, part_type, text: string) {
	strings.write_string(b, `{"type":`)
	write_json_string(b, part_type)
	strings.write_string(b, `,"text":`)
	write_json_string(b, text)
	strings.write_byte(b, '}')
}

/*
Map the message list to Responses input items. Tool results become
function_call_output keyed by call_id, assistant tool calls become
function_call items. Media degrades to input_image for user images; other
kinds flatten to a text note.
*/
@(private)
write_responses_input :: proc(b: ^strings.Builder, msgs: []Message) {
	strings.write_string(b, `,"input":[`)
	first := true
	for m in msgs {
		if m.role == .System {
			continue
		}
		switch m.role {
		case .User:
			if !first {
				strings.write_byte(b, ',')
			}
			first = false
			strings.write_string(b, `{"type":"message","role":"user","content":[`)
			wrote := false
			if len(m.content) > 0 || len(m.media) == 0 {
				text := m.content
				if len(text) == 0 {
					text = " "
				}
				write_responses_input_text(b, "input_text", text)
				wrote = true
			}
			for mp in m.media {
				if wrote {
					strings.write_byte(b, ',')
				}
				if mp.kind == .Image {
					strings.write_string(b, `{"type":"input_image","image_url":"data:`)
					strings.write_string(b, mp.mime)
					strings.write_string(b, ";base64,")
					strings.write_string(b, mp.data_b64)
					strings.write_string(b, `"}`)
				} else {
					kind := mp.kind == .Audio ? "audio" : "video"
					label := mp.label
					if len(label) == 0 {
						label = mp.mime
					}
					write_responses_input_text(b, "input_text", fmt.tprintf("[attached %s: %s]", kind, label))
				}
				wrote = true
			}
			strings.write_string(b, "]}")
		case .Assistant:
			if len(m.content) > 0 || len(m.tool_calls) == 0 {
				if !first {
					strings.write_byte(b, ',')
				}
				first = false
				text := m.content
				if len(text) == 0 {
					text = " "
				}
				strings.write_string(b, `{"type":"message","role":"assistant","content":[`)
				write_responses_input_text(b, "output_text", text)
				strings.write_string(b, "]}")
			}
			for tc in m.tool_calls {
				if !first {
					strings.write_byte(b, ',')
				}
				first = false
				strings.write_string(b, `{"type":"function_call","call_id":`)
				write_json_string(b, tc.id)
				strings.write_string(b, `,"name":`)
				write_json_string(b, tc.name)
				strings.write_string(b, `,"arguments":`)
				write_json_string(b, tool_args_valid_json(tc.arguments))
				strings.write_byte(b, '}')
			}
		case .Tool:
			if !first {
				strings.write_byte(b, ',')
			}
			first = false
			strings.write_string(b, `{"type":"function_call_output","call_id":`)
			write_json_string(b, m.tool_call_id)
			strings.write_string(b, `,"output":`)
			write_json_string(b, m.content)
			strings.write_byte(b, '}')
		case .System:
		}
	}
	strings.write_string(b, "]")
}

build_responses_body :: proc(p: ^Provider, req: Chat_Request, model: string) -> string {
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	strings.write_string(&b, `{"model":`)
	write_json_string(&b, model)
	if sys := responses_system_text(req); len(sys) > 0 {
		strings.write_string(&b, `,"instructions":`)
		write_json_string(&b, sys)
	}
	write_responses_input(&b, req.messages)
	if len(req.tools_json) > 0 {
		write_responses_tools(&b, req.tools_json)
		if len(req.tool_choice) > 0 {
			strings.write_string(&b, `,"tool_choice":`)
			write_json_string(&b, req.tool_choice)
		}
	}
	if req.max_tokens > 0 {
		fmt.sbprintf(&b, `,"max_output_tokens":%d`, req.max_tokens)
	}
	if len(strings.trim_space(req.reasoning_effort)) > 0 {
		strings.write_string(&b, `,"reasoning":{"effort":`)
		write_json_string(&b, strings.to_lower(strings.trim_space(req.reasoning_effort), context.temp_allocator))
		strings.write_string(&b, `}`)
	}
	// Stateless turn: nothing references a previous_response_id, and
	// store:false keeps provider-side retention off on Zen.
	strings.write_string(&b, `,"store":false,"stream":false}`)
	return strings.to_string(b)
}
