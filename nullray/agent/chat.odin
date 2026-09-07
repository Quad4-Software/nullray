/*
Single chat call with optional streaming bridge.
*/

package agent

import "core:strings"
import "nullray:provider"

Delta_Ctx :: struct {
	cfg: Config,
}

@(private)
delta_bridge :: proc(kind: provider.Delta_Kind, text: string, user: rawptr) {
	ctx := cast(^Delta_Ctx)user
	switch kind {
	case .Content:
		emit(ctx.cfg, .Delta, text)
	case .Reasoning:
		emit(ctx.cfg, .Reasoning_Delta, text)
	}
}

@(private)
single_chat :: proc(p: ^provider.Provider, msgs: []provider.Message, model, tools_json: string, cfg: Config, allocator := context.allocator) -> provider.Chat_Response {
	choice := ""
	if len(tools_json) > 0 {
		choice = "auto"
	}
	req := provider.Chat_Request{
		model = model,
		messages = msgs,
		stream = cfg.stream,
		tools_json = tools_json,
		tool_choice = choice,
		reasoning_effort = cfg.reasoning_effort,
		max_tokens = cfg.max_tokens,
	}
	if cfg.stream {
		dctx := Delta_Ctx{cfg = cfg}
		res := provider.openai_chat_stream(p, req, delta_bridge, &dctx, allocator)
		if !res.ok {
			err := res.err
			if len(err) == 0 {
				err = strings.clone("chat failed", allocator)
			} else {
				err = strings.clone(err, allocator)
			}
			provider.destroy_chat_response(&res)
			return provider.Chat_Response{ok = false, err = err}
		}
		return res
	}
	res := p.chat(p, req)
	if !res.ok {
		err := res.err
		if len(err) == 0 {
			err = strings.clone("chat failed", allocator)
		} else {
			err = strings.clone(err, allocator)
		}
		provider.destroy_chat_response(&res)
		return provider.Chat_Response{ok = false, err = err}
	}
	return res
}

@(private)
clone_messages :: proc(msgs: []provider.Message, allocator := context.allocator) -> [dynamic]provider.Message {
	out := make([dynamic]provider.Message, 0, len(msgs), allocator)
	for m in msgs {
		append(&out, provider.clone_message(m, allocator))
	}
	return out
}

