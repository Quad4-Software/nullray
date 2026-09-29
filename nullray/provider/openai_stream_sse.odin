// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
SSE line handling for OpenAI chat streaming: JSON chunk parse, error capture,
delta emission, and tool_calls accumulation.
*/

package provider

import "core:encoding/json"
import "core:mem"
import "core:strconv"
import "core:strings"
import "core:sync"
import "nullray:constants"

@(private)
stream_accum_reset :: proc(accum: ^Stream_Accum) {
	strings.builder_destroy(&accum.content)
	strings.builder_destroy(&accum.reasoning)
	destroy_tool_calls(accum.tool_calls[:])
	delete(accum.tool_calls)
	delete(accum.tool_sealed)
	delete(accum.err)
	delete(accum.finish)
	delete(accum.model)
}

@(private)
sse_line_cb :: proc(line: string, user: rawptr) {
	accum := cast(^Stream_Accum)user
	// Scratch only for this line. Never free_all the shared temp allocator here
	// curl POSTFIELDS/URL and agent tools_json may still live on it.
	scratch := make([]byte, 128 * 1024, context.allocator)
	defer delete(scratch)
	arena: mem.Arena
	mem.arena_init(&arena, scratch)
	alloc := mem.arena_allocator(&arena)
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
	doc, err := json.parse_string(payload, .JSON, allocator = alloc)
	if err != .None {
		return
	}
	obj, ok := doc.(json.Object)
	if !ok {
		return
	}
	if err_v, has_err := obj["error"]; has_err {
		if err_obj, eok := err_v.(json.Object); eok {
			status := 0
			if code_v, cok := err_obj["code"]; cok {
				#partial switch c in code_v {
				case json.Integer:
					status = int(c)
				case json.Float:
					status = int(c)
				case json.String:
					if n, nok := strconv.parse_int(string(c)); nok {
						status = n
					}
				}
			}
			if msg, mok := err_obj["message"]; mok {
				if s, sok := msg.(json.String); sok {
					sync.mutex_lock(&accum.mu)
					delete(accum.err)
					accum.err = strings.clone(string(s))
					accum.err_status = status
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
		if parsed.total_tokens > 0 || parsed.prompt_tokens > 0 || parsed.completion_tokens > 0 || parsed.cost_known || parsed.reasoning_tokens > 0 {
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
		builder := &accum.content
		if kind != .Content {
			builder = &accum.reasoning
		}
		if strings.builder_len(builder^) >= constants.MAX_STREAMING_CHARS {
			sync.mutex_unlock(&accum.mu)
			return
		}
		remain := constants.MAX_STREAMING_CHARS - strings.builder_len(builder^)
		piece := chunk
		if len(piece) > remain {
			piece = piece[:remain]
		}
		strings.write_string(builder, piece)
		cb := accum.on_delta
		u := accum.user
		sync.mutex_unlock(&accum.mu)
		if cb != nil {
			cb(kind, piece, u)
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
	if rcv, rcok := dobj["reasoning_content"]; rcok {
		if s, sok := rcv.(json.String); sok {
			emit_delta(accum, .Reasoning, string(s))
		}
	}
	if tv, tok := dobj["thinking"]; tok {
		if s, sok := tv.(json.String); sok {
			emit_delta(accum, .Reasoning, string(s))
		}
	}
	if rdv, rdok := dobj["reasoning_details"]; rdok {
		chunk := extract_reasoning_details(rdv, alloc)
		emit_delta(accum, .Reasoning, chunk)
	}
	if tcv, tok := dobj["tool_calls"]; tok {
		if tc_arr, taok := tcv.(json.Array); taok {
			newly := make([dynamic]int, alloc)
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
				id_s, name_s, args_s := "", "", ""
				if idv, iok := tc_obj["id"]; iok {
					if s, sok := idv.(json.String); sok {
						id_s = string(s)
					}
				}
				if fnv, fok := tc_obj["function"]; fok {
					if fn, fnok := fnv.(json.Object); fnok {
						if nv, nok := fn["name"]; nok {
							if s, sok := nv.(json.String); sok {
								name_s = string(s)
							}
						}
						if av, aok := fn["arguments"]; aok {
							if s, sok := av.(json.String); sok {
								args_s = string(s)
							}
						}
					}
				}
				for len(accum.tool_calls) <= idx {
					append(&accum.tool_calls, Tool_Call{})
				}
				for len(accum.tool_sealed) <= idx {
					append(&accum.tool_sealed, false)
				}
				tc := &accum.tool_calls[idx]
				if len(id_s) > 0 && len(tc.id) == 0 {
					tc.id = strings.clone(id_s)
				}
				if len(name_s) > 0 && len(tc.name) == 0 {
					tc.name = strings.clone(name_s)
				}
				if len(args_s) > 0 {
					old := tc.arguments
					tc.arguments = strings.concatenate({tc.arguments, args_s})
					delete(old)
				}
				for j in 0 ..< idx {
					if j < len(accum.tool_sealed) && !accum.tool_sealed[j] {
						accum.tool_sealed[j] = true
						append(&newly, j)
					}
				}
			}
			cb := accum.on_tool_seal
			su := accum.seal_user
			sync.mutex_unlock(&accum.mu)
			if cb != nil {
				for i in newly {
					sync.mutex_lock(&accum.mu)
					tc := accum.tool_calls[i]
					id := tc.id
					name := tc.name
					args := tc.arguments
					sync.mutex_unlock(&accum.mu)
					cb(i, id, name, args, su)
				}
			}
		}
	}
}
