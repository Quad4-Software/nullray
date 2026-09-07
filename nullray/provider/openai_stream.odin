/*
OpenAI SSE chat streaming: content, reasoning, and tool_calls deltas.
*/

package provider

import "core:encoding/json"
import "core:fmt"
import "core:strings"
import "core:sync"
import "nullray:constants"
import "nullray:http"

Delta_Kind :: enum {
	Content,
	Reasoning,
}

Delta_Proc :: #type proc(kind: Delta_Kind, text: string, user: rawptr)

Stream_Accum :: struct {
	content:     strings.Builder,
	reasoning:   strings.Builder,
	tool_calls:  [dynamic]Tool_Call,
	finish:      string,
	model:       string,
	err:         string,
	usage:       Usage,
	on_delta:    Delta_Proc,
	user:        rawptr,
	mu:          sync.Mutex,
	ok:          bool,
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
	strings.write_string(&b, `],"stream":true,"stream_options":{"include_usage":true}`)
	write_max_tokens_json(&b, p, req.max_tokens, model)
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

	accum: Stream_Accum
	strings.builder_init(&accum.content, allocator)
	strings.builder_init(&accum.reasoning, allocator)
	accum.tool_calls = make([dynamic]Tool_Call, allocator)
	accum.on_delta = on_delta
	accum.user = user
	accum.ok = true

	url := http.join_url(p.base_url, "/chat/completions")
	res := http.post_json_stream(url, headers[:], body, sse_line_cb, &accum, constants.HTTP_TIMEOUT_SEC)
	if !res.ok {
		delete(accum.err)
		strings.builder_destroy(&accum.content)
		strings.builder_destroy(&accum.reasoning)
		destroy_tool_calls(accum.tool_calls[:])
		delete(accum.tool_calls)
		err := provider_http_error(res, allocator)
		return Chat_Response{ok = false, err = err}
	}
	if len(accum.err) > 0 {
		out_err := strings.clone(accum.err, allocator)
		strings.builder_destroy(&accum.content)
		strings.builder_destroy(&accum.reasoning)
		destroy_tool_calls(accum.tool_calls[:])
		delete(accum.tool_calls)
		delete(accum.err)
		delete(accum.finish)
		delete(accum.model)
		return Chat_Response{ok = false, err = out_err}
	}

	content := strings.clone(strings.to_string(accum.content), allocator)
	reasoning := strings.clone(strings.to_string(accum.reasoning), allocator)
	strings.builder_destroy(&accum.content)
	strings.builder_destroy(&accum.reasoning)
	calls := accum.tool_calls[:]
	if len(content) == 0 && len(reasoning) == 0 && len(calls) == 0 {
		delete(content)
		delete(reasoning)
		destroy_tool_calls(calls)
		delete(accum.finish)
		delete(accum.model)
		return Chat_Response{ok = false, err = strings.clone("empty model response (unavailable or exhausted)", allocator)}
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

@(private)
sse_line_cb :: proc(line: string, user: rawptr) {
	accum := cast(^Stream_Accum)user
	trimmed := strings.trim_space(line)
	if len(trimmed) == 0 {
		return
	}
	if !strings.has_prefix(trimmed, "data:") {
		return
	}
	payload := strings.trim_space(trimmed[5:])
	if payload == "[DONE]" {
		return
	}
	doc, err := json.parse_string(payload, .JSON, allocator = context.temp_allocator)
	if err != .None {
		return
	}
	obj, ok := doc.(json.Object)
	if !ok {
		return
	}
	if err_v, has_err := obj["error"]; has_err {
		if err_obj, eok := err_v.(json.Object); eok {
			if msg, mok := err_obj["message"]; mok {
				if s, sok := msg.(json.String); sok {
					sync.mutex_lock(&accum.mu)
					delete(accum.err)
					accum.err = strings.clone(string(s))
					accum.ok = false
					sync.mutex_unlock(&accum.mu)
				}
			}
		}
		return
	}
	if m, mok := obj["model"]; mok {
		if s, sok := m.(json.String); sok {
			sync.mutex_lock(&accum.mu)
			if len(accum.model) == 0 {
				accum.model = strings.clone(string(s))
			}
			sync.mutex_unlock(&accum.mu)
		}
	}
	if uv, uok := obj["usage"]; uok {
		parsed := parse_usage_value(uv)
		if parsed.total_tokens > 0 || parsed.prompt_tokens > 0 || parsed.completion_tokens > 0 {
			sync.mutex_lock(&accum.mu)
			accum.usage = parsed
			sync.mutex_unlock(&accum.mu)
		}
	}
	choices, cok := obj["choices"]
	if !cok {
		return
	}
	arr, aok := choices.(json.Array)
	if !aok || len(arr) == 0 {
		return
	}
	choice, chok := arr[0].(json.Object)
	if !chok {
		return
	}
	if fr, fok := choice["finish_reason"]; fok {
		if s, sok := fr.(json.String); sok {
			sync.mutex_lock(&accum.mu)
			delete(accum.finish)
			accum.finish = strings.clone(string(s))
			sync.mutex_unlock(&accum.mu)
		}
	}
	delta, dok := choice["delta"]
	if !dok {
		return
	}
	dobj, dok2 := delta.(json.Object)
	if !dok2 {
		return
	}
	emit_delta :: proc(accum: ^Stream_Accum, kind: Delta_Kind, chunk: string) {
		if len(chunk) == 0 {
			return
		}
		sync.mutex_lock(&accum.mu)
		if kind == .Content {
			strings.write_string(&accum.content, chunk)
		} else {
			strings.write_string(&accum.reasoning, chunk)
		}
		cb := accum.on_delta
		u := accum.user
		sync.mutex_unlock(&accum.mu)
		if cb != nil {
			cb(kind, chunk, u)
		}
	}
	if cval, cok2 := dobj["content"]; cok2 {
		if s, sok := cval.(json.String); sok {
			emit_delta(accum, .Content, string(s))
		}
	}
	if rval, rok := dobj["reasoning"]; rok {
		if s, sok := rval.(json.String); sok {
			emit_delta(accum, .Reasoning, string(s))
		}
	}
	if rdv, rdok := dobj["reasoning_details"]; rdok {
		chunk := extract_reasoning_details(rdv)
		emit_delta(accum, .Reasoning, chunk)
	}
	if tcv, tok := dobj["tool_calls"]; tok {
		if tc_arr, taok := tcv.(json.Array); taok {
			sync.mutex_lock(&accum.mu)
			for item in tc_arr {
				tc_obj, to_ok := item.(json.Object)
				if !to_ok {
					continue
				}
				idx := 0
				if iv, iok := tc_obj["index"]; iok {
					#partial switch n in iv {
					case json.Integer:
						idx = int(n)
					case json.Float:
						idx = int(n)
					}
				}
				for len(accum.tool_calls) <= idx {
					append(&accum.tool_calls, Tool_Call{})
				}
				tc := &accum.tool_calls[idx]
				if idv, iok := tc_obj["id"]; iok {
					if s, sok := idv.(json.String); sok {
						if len(tc.id) == 0 {
							tc.id = strings.clone(string(s))
						}
					}
				}
				if fnv, fok := tc_obj["function"]; fok {
					if fn, fnok := fnv.(json.Object); fnok {
						if nv, nok := fn["name"]; nok {
							if s, sok := nv.(json.String); sok {
								if len(tc.name) == 0 {
									tc.name = strings.clone(string(s))
								}
							}
						}
						if av, aok := fn["arguments"]; aok {
							if s, sok := av.(json.String); sok {
								tc.arguments = strings.concatenate({tc.arguments, string(s)})
							}
						}
					}
				}
			}
			sync.mutex_unlock(&accum.mu)
		}
	}
}
