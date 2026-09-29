// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Anthropic Messages SSE line handling: content_block deltas, tool_use input
accumulation, and message_delta usage.
*/

package provider

import "core:encoding/json"
import "core:mem"
import "core:strings"
import "core:sync"
import "nullray:constants"

@(private)
anthropic_error_status :: proc(err_type: string) -> int {
	switch err_type {
	case "rate_limit_error":
		return 429
	case "authentication_error":
		return 401
	case "permission_error":
		return 403
	case "not_found_error":
		return 404
	case "overloaded_error":
		return 503
	case "invalid_request_error":
		return 400
	}
	return 500
}

@(private)
anthropic_emit_delta :: proc(accum: ^Stream_Accum, kind: Delta_Kind, chunk: string) {
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

// Seal a finished tool_use block so the agent sees a complete call.
@(private)
anthropic_seal_block :: proc(accum: ^Stream_Accum, block_idx: int, newly: ^[dynamic]int) {
	if block_idx < 0 || block_idx >= len(accum.block_tool) {
		return
	}
	tc_idx := accum.block_tool[block_idx]
	if tc_idx < 0 || tc_idx >= len(accum.tool_calls) {
		return
	}
	for len(accum.tool_sealed) <= tc_idx {
		append(&accum.tool_sealed, false)
	}
	if !accum.tool_sealed[tc_idx] {
		accum.tool_sealed[tc_idx] = true
		append(newly, tc_idx)
	}
}

@(private)
anthropic_sse_line_cb :: proc(line: string, user: rawptr) {
	accum := cast(^Stream_Accum)user
	scratch := make([]byte, 128 * 1024, context.allocator)
	defer delete(scratch)
	arena: mem.Arena
	mem.arena_init(&arena, scratch)
	alloc := mem.arena_allocator(&arena)
	trimmed := strings.trim_space(line)
	if len(trimmed) == 0 || !strings.has_prefix(trimmed, "data:") {
		return
	}
	payload := strings.trim_space(trimmed[5:])
	doc, err := json.parse_string(payload, .JSON, allocator = alloc)
	if err != .None {
		return
	}
	obj, ok := doc.(json.Object)
	if !ok {
		return
	}
	etype := ""
	if tv, tok := obj["type"]; tok {
		if s, sok := tv.(json.String); sok {
			etype = string(s)
		}
	}
	switch etype {
	case "error":
		if ev, eok := obj["error"]; eok {
			if eobj, eeok := ev.(json.Object); eeok {
				msg := ""
				if mv, mok := eobj["message"]; mok {
					if s, sok := mv.(json.String); sok {
						msg = string(s)
					}
				}
				etype2 := ""
				if tv2, tok2 := eobj["type"]; tok2 {
					if s, sok := tv2.(json.String); sok {
						etype2 = string(s)
					}
				}
				sync.mutex_lock(&accum.mu)
				delete(accum.err)
				accum.err = strings.clone(msg)
				accum.err_status = anthropic_error_status(etype2)
				accum.ok = false
				sync.mutex_unlock(&accum.mu)
			}
		}
	case "message_start":
		if mv, mok := obj["message"]; mok {
			if mobj, mook := mv.(json.Object); mook {
				if mv2, mok2 := mobj["model"]; mok2 {
					if s, sok := mv2.(json.String); sok {
						sync.mutex_lock(&accum.mu)
						if len(accum.model) == 0 {
							accum.model = strings.clone(string(s))
						}
						sync.mutex_unlock(&accum.mu)
					}
				}
				if uv, uok := mobj["usage"]; uok {
					if uobj, uook := uv.(json.Object); uook {
						u := anthropic_usage(uobj)
						sync.mutex_lock(&accum.mu)
						accum.usage.prompt_tokens = u.prompt_tokens
						accum.usage.total_tokens = u.prompt_tokens + accum.usage.completion_tokens
						sync.mutex_unlock(&accum.mu)
					}
				}
			}
		}
	case "content_block_start":
		idx := json_int_field(obj, "index")
		if cbv, cbok := obj["content_block"]; cbok {
			if cbobj, cbok2 := cbv.(json.Object); cbok2 {
				btype := ""
				if tv, tok := cbobj["type"]; tok {
					if s, sok := tv.(json.String); sok {
						btype = string(s)
					}
				}
				sync.mutex_lock(&accum.mu)
				for len(accum.block_tool) <= idx {
					append(&accum.block_tool, -1)
				}
				if btype == "tool_use" {
					tc: Tool_Call
					if iv, iok := cbobj["id"]; iok {
						if s, sok := iv.(json.String); sok {
							tc.id = strings.clone(string(s))
						}
					}
					if nv, nok := cbobj["name"]; nok {
						if s, sok := nv.(json.String); sok {
							tc.name = strings.clone(string(s))
						}
					}
					append(&accum.tool_calls, tc)
					accum.block_tool[idx] = len(accum.tool_calls) - 1
				}
				sync.mutex_unlock(&accum.mu)
			}
		}
	case "content_block_delta":
		idx := json_int_field(obj, "index")
		dv, dok := obj["delta"]
		dobj, dook := dv.(json.Object)
		if !dok || !dook {
			return
		}
		dtype := ""
		if tv, tok := dobj["type"]; tok {
			if s, sok := tv.(json.String); sok {
				dtype = string(s)
			}
		}
		switch dtype {
		case "text_delta":
			if tv, tok := dobj["text"]; tok {
				if s, sok := tv.(json.String); sok {
					anthropic_emit_delta(accum, .Content, string(s))
				}
			}
		case "thinking_delta":
			if tv, tok := dobj["thinking"]; tok {
				if s, sok := tv.(json.String); sok {
					anthropic_emit_delta(accum, .Reasoning, string(s))
				}
			}
		case "input_json_delta":
			if tv, tok := dobj["partial_json"]; tok {
				if s, sok := tv.(json.String); sok && len(s) > 0 {
					sync.mutex_lock(&accum.mu)
					if idx >= 0 && idx < len(accum.block_tool) {
						tc_idx := accum.block_tool[idx]
						if tc_idx >= 0 && tc_idx < len(accum.tool_calls) {
							tc := &accum.tool_calls[tc_idx]
							old := tc.arguments
							tc.arguments = strings.concatenate({old, string(s)})
							delete(old)
						}
					}
					sync.mutex_unlock(&accum.mu)
				}
			}
		}
	case "content_block_stop":
		idx := json_int_field(obj, "index")
		newly := make([dynamic]int, alloc)
		sync.mutex_lock(&accum.mu)
		anthropic_seal_block(accum, idx, &newly)
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
	case "message_delta":
		if dv, dok := obj["delta"]; dok {
			if dobj, dook := dv.(json.Object); dook {
				if sv, sok := dobj["stop_reason"]; sok {
					if s, ssok := sv.(json.String); ssok {
						sync.mutex_lock(&accum.mu)
						delete(accum.finish)
						accum.finish = strings.clone(string(s))
						sync.mutex_unlock(&accum.mu)
					}
				}
			}
		}
		if uv, uok := obj["usage"]; uok {
			if uobj, uook := uv.(json.Object); uook {
				out := json_int_field(uobj, "output_tokens")
				sync.mutex_lock(&accum.mu)
				if out > 0 {
					accum.usage.completion_tokens = out
				}
				accum.usage.total_tokens = accum.usage.prompt_tokens + accum.usage.completion_tokens
				sync.mutex_unlock(&accum.mu)
			}
		}
	case "message_stop", "ping":
	}
}

