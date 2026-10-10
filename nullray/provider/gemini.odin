// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Google generateContent surface for OpenCode Zen models routed to
/zen/v1/models/{model}:generateContent (gemini-*).
*/

package provider

import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:strings"
import "nullray:constants"
import "nullray:http"

gemini_chat :: proc(p: ^Provider, req: Chat_Request, allocator := context.allocator) -> Chat_Response {
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
	append(&headers, "Content-Type: application/json")
	if len(p.api_key) > 0 {
		append(&headers, fmt.tprintf("Authorization: Bearer %s", p.api_key))
		append(&headers, fmt.tprintf("x-goog-api-key: %s", p.api_key))
	}
	append_opencode_headers(&headers, p, req.session_id)

	// /models/{model}:generateContent under the provider base.
	rel := fmt.tprintf("/models/%s:generateContent", model)
	url := http.join_url(p.base_url, rel)

	retries := http_retry_limit()
	last: http.Response

	temp_epoch := runtime.default_temp_allocator_temp_begin()
	defer runtime.default_temp_allocator_temp_end(temp_epoch)

	for attempt in 0 ..= retries {
		if http.cancel_requested() {
			return Chat_Response{ok = false, err = strings.clone("cancelled", allocator)}
		}
		body := build_gemini_body(p, req, model)
		last = http.post_json(url, headers[:], body, http_timeout_sec(), context.temp_allocator)
		if last.ok {
			return parse_gemini_response(last.body, allocator)
		}
		if !http_status_retryable(last.status) || attempt >= retries {
			break
		}
		retry_wait(attempt, last.retry_after)
	}

	err := provider_http_error(last, p, allocator)
	return Chat_Response{ok = false, err = err}
}

gemini_chat_stream :: proc(
	p: ^Provider,
	req: Chat_Request,
	on_delta: Delta_Proc,
	user: rawptr,
	allocator := context.allocator,
) -> Chat_Response {
	res := gemini_chat(p, req, allocator)
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
OpenAI tools_json -> Gemini functionDeclarations. The Google schema is
OpenAPI-ish; the parameters object passes through unchanged.
*/
@(private)
write_gemini_tools :: proc(b: ^strings.Builder, tools_json: string) {
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
		strings.write_string(&tb, `{"name":`)
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
		strings.write_string(b, `,"tools":[{"functionDeclarations":[`)
		strings.write_string(b, strings.to_string(tb))
		strings.write_string(b, "]}]")
	}
}

@(private)
write_gemini_text_part :: proc(b: ^strings.Builder, text: string) {
	strings.write_string(b, `{"text":`)
	write_json_string(b, text)
	strings.write_byte(b, '}')
}

/*
Message list -> Gemini contents. system text is hoisted into
systemInstruction. Tool results ride as user-role functionResponse parts
keyed by function name, assistant tool calls as model-role functionCall
parts whose args object comes from the raw args JSON.
*/
@(private)
write_gemini_contents :: proc(b: ^strings.Builder, msgs: []Message) {
	strings.write_string(b, `"contents":[`)
	first := true
	for m in msgs {
		if m.role == .System {
			continue
		}
		role := m.role == .Assistant ? "model" : "user"
		parts: strings.Builder
		strings.builder_init(&parts, context.temp_allocator)
		wrote := false
		switch m.role {
		case .User:
			if len(m.content) > 0 || len(m.media) == 0 {
				write_gemini_text_part(&parts, len(m.content) > 0 ? m.content : " ")
				wrote = true
			}
			for mp in m.media {
				if wrote {
					strings.write_byte(&parts, ',')
				}
				if mp.kind == .Image {
					strings.write_string(&parts, `{"inlineData":{"mimeType":`)
					write_json_string(&parts, mp.mime)
					strings.write_string(&parts, `,"data":`)
					write_json_string(&parts, mp.data_b64)
					strings.write_string(&parts, "}}")
				} else {
					kind := mp.kind == .Audio ? "audio" : "video"
					label := mp.label
					if len(label) == 0 {
						label = mp.mime
					}
					write_gemini_text_part(&parts, fmt.tprintf("[attached %s: %s]", kind, label))
				}
				wrote = true
			}
		case .Assistant:
			if len(m.content) > 0 || len(m.tool_calls) == 0 {
				write_gemini_text_part(&parts, len(m.content) > 0 ? m.content : " ")
				wrote = true
			}
			for tc in m.tool_calls {
				if wrote {
					strings.write_byte(&parts, ',')
				}
				strings.write_string(&parts, `{"functionCall":{"name":`)
				write_json_string(&parts, tc.name)
				strings.write_string(&parts, `,"args":`)
				args := strings.trim_space(tool_args_valid_json(tc.arguments))
				strings.write_string(&parts, len(args) > 0 ? args : "{}")
				strings.write_string(&parts, `}`)
				if len(tc.signature) > 0 {
					strings.write_string(&parts, `,"thoughtSignature":`)
					write_json_string(&parts, tc.signature)
				}
				strings.write_string(&parts, `}`)
				wrote = true
			}
		case .Tool:
			strings.write_string(&parts, `{"functionResponse":{"name":`)
			name := m.name
			if len(name) == 0 {
				name = m.tool_call_id
			}
			write_json_string(&parts, name)
			strings.write_string(&parts, `,"response":{"result":`)
			write_json_string(&parts, m.content)
			strings.write_string(&parts, "}}}")
			wrote = true
		case .System:
		}
		if !wrote {
			strings.builder_destroy(&parts)
			continue
		}
		if !first {
			strings.write_byte(b, ',')
		}
		first = false
		strings.write_string(b, `{"role":`)
		write_json_string(b, role)
		strings.write_string(b, `,"parts":[`)
		strings.write_string(b, strings.to_string(parts))
		strings.write_string(b, "]}")
	}
	strings.write_string(b, "]")
}

build_gemini_body :: proc(p: ^Provider, req: Chat_Request, model: string) -> string {
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	strings.write_string(&b, `{`)
	write_gemini_contents(&b, req.messages)
	if sys := responses_system_text(req); len(sys) > 0 {
		strings.write_string(&b, `,"systemInstruction":{"parts":[{"text":`)
		write_json_string(&b, sys)
		strings.write_string(&b, "}]}")
	}
	if len(req.tools_json) > 0 {
		write_gemini_tools(&b, req.tools_json)
	}
	cfg: strings.Builder
	strings.builder_init(&cfg, context.temp_allocator)
	wrote_cfg := false
	if req.max_tokens > 0 {
		fmt.sbprintf(&cfg, `"maxOutputTokens":%d`, req.max_tokens)
		wrote_cfg = true
	}
	if supports_sampling_params(p, model) {
		if req.temperature_set {
			if wrote_cfg {
				strings.write_byte(&cfg, ',')
			}
			fmt.sbprintf(&cfg, `"temperature":%.4g`, req.temperature)
			wrote_cfg = true
		}
		if req.top_p_set {
			if wrote_cfg {
				strings.write_byte(&cfg, ',')
			}
			fmt.sbprintf(&cfg, `"topP":%.4g`, req.top_p)
			wrote_cfg = true
		}
	}
	if wrote_cfg {
		strings.write_string(&b, `,"generationConfig":{`)
		strings.write_string(&b, strings.to_string(cfg))
		strings.write_byte(&b, '}')
	}
	strings.write_byte(&b, '}')
	return strings.to_string(b)
}
