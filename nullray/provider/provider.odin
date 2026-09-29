// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Extensible model provider interface with tool calling.
*/

package provider

import "core:strings"

Role :: enum {
	System,
	User,
	Assistant,
	Tool,
}

Tool_Call :: struct {
	id:        string,
	name:      string,
	arguments: string,
}

Media_Kind :: enum {
	Image,
	Audio,
	Video,
}

Media_Part :: struct {
	kind:     Media_Kind,
	mime:     string,
	data_b64: string,
	label:    string,
}

Message :: struct {
	role:         Role,
	content:      string,
	reasoning:    string,
	tool_call_id: string,
	tool_calls:   []Tool_Call,
	name:         string,
	cacheable:    bool,
	media:        []Media_Part,
}

Chat_Request :: struct {
	model:            string,
	messages:         []Message,
	stream:           bool,
	tools_json:       string,
	tool_choice:      string,
	reasoning_effort: string,
	max_tokens:       int,
	temperature:      f64,
	top_p:            f64,
	temperature_set:  bool,
	top_p_set:        bool,
	on_tool_seal:     Tool_Seal_Proc,
	seal_user:        rawptr,
	session_id:       string,
}

Chat_Response :: struct {
	ok:            bool,
	content:       string,
	reasoning:     string,
	model:         string,
	err:           string,
	tool_calls:    []Tool_Call,
	finish_reason: string,
	usage:         Usage,
}

Usage :: struct {
	prompt_tokens:      int,
	completion_tokens:  int,
	total_tokens:       int,
	reasoning_tokens:   int,
	// Cache hits and writes, where the provider reports them (Anthropic,
	// OpenRouter). prompt_tokens still counts them so cost stays right.
	cache_read_tokens:  int,
	cache_write_tokens: int,
	cost_usd:           f64,
	cost_known:         bool,
}

Model_Info :: struct {
	id:                   string,
	name:                 string,
	reasoning_efforts:    []string,
	reasoning_default:    string,
	reasoning_default_on: bool,
	reasoning_mandatory:  bool,
	has_reasoning_meta:   bool,
	// Catalog enrichment (models.dev). Zero means unknown.
	context_limit:        int,
	output_limit:         int,
	cost_in:              f64,
	cost_out:             f64,
	has_cost:             bool,
}

Delta_Kind :: enum {
	Content,
	Reasoning,
}

Delta_Proc :: #type proc(kind: Delta_Kind, text: string, user: rawptr)

// Fired when a streamed tool_calls index is sealed (next index appeared or stream ended).
// Never means args are final because JSON happened to parse mid-stream.
Tool_Seal_Proc :: #type proc(idx: int, id, name, args: string, user: rawptr)

Embed_Request :: struct {
	model: string,
	input: []string,
}

Embed_Response :: struct {
	ok:      bool,
	model:   string,
	vectors: [][]f32,
	err:     string,
}

Provider :: struct {
	id:            string,
	name:          string,
	base_url:      string,
	api_key:       string,
	default_model: string,
	chat:          Chat_Proc,
	stream:        Stream_Proc,
	list_models:   List_Proc,
	embed:         Embed_Proc,
	user_data:     rawptr,
}

Chat_Proc :: #type proc(p: ^Provider, req: Chat_Request, allocator := context.allocator) -> Chat_Response
List_Proc :: #type proc(p: ^Provider, allocator := context.allocator) -> (models: []Model_Info, err: string)
Embed_Proc :: #type proc(p: ^Provider, req: Embed_Request, allocator := context.allocator) -> Embed_Response
Stream_Proc :: #type proc(
	p: ^Provider,
	req: Chat_Request,
	on_delta: Delta_Proc,
	user: rawptr,
	allocator := context.allocator,
) -> Chat_Response

destroy_embed_response :: proc(res: ^Embed_Response) {
	if res == nil {
		return
	}
	for v in res.vectors {
		delete(v)
	}
	delete(res.vectors)
	delete(res.model)
	delete(res.err)
	res^ = {}
}

role_string :: proc(r: Role) -> string {
	switch r {
	case .System:
		return "system"
	case .User:
		return "user"
	case .Assistant:
		return "assistant"
	case .Tool:
		return "tool"
	}
	return "user"
}

clone_tool_call :: proc(tc: Tool_Call, allocator := context.allocator) -> Tool_Call {
	return Tool_Call{
		id = strings.clone(tc.id, allocator),
		name = strings.clone(tc.name, allocator),
		arguments = strings.clone(tc.arguments, allocator),
	}
}

destroy_tool_calls :: proc(calls: []Tool_Call) {
	for c in calls {
		delete(c.id)
		delete(c.name)
		delete(c.arguments)
	}
}

destroy_tool_calls_owned :: proc(calls: []Tool_Call) {
	destroy_tool_calls(calls)
	delete(calls)
}

clone_media_part :: proc(mp: Media_Part, allocator := context.allocator) -> Media_Part {
	return Media_Part{
		kind = mp.kind,
		mime = strings.clone(mp.mime, allocator),
		data_b64 = strings.clone(mp.data_b64, allocator),
		label = strings.clone(mp.label, allocator),
	}
}

destroy_media_parts :: proc(parts: []Media_Part) {
	for mp in parts {
		delete(mp.mime)
		delete(mp.data_b64)
		delete(mp.label)
	}
}

destroy_media_parts_owned :: proc(parts: []Media_Part) {
	destroy_media_parts(parts)
	delete(parts)
}

clone_message :: proc(m: Message, allocator := context.allocator) -> Message {
	out := Message{
		role = m.role,
		content = strings.clone(m.content, allocator),
		reasoning = strings.clone(m.reasoning, allocator),
		tool_call_id = strings.clone(m.tool_call_id, allocator),
		name = strings.clone(m.name, allocator),
		cacheable = m.cacheable,
	}
	if len(m.tool_calls) > 0 {
		out.tool_calls = make([]Tool_Call, len(m.tool_calls), allocator)
		for tc, i in m.tool_calls {
			out.tool_calls[i] = clone_tool_call(tc, allocator)
		}
	}
	if len(m.media) > 0 {
		out.media = make([]Media_Part, len(m.media), allocator)
		for mp, i in m.media {
			out.media[i] = clone_media_part(mp, allocator)
		}
	}
	return out
}

destroy_message :: proc(m: Message) {
	delete(m.content)
	delete(m.reasoning)
	delete(m.tool_call_id)
	delete(m.name)
	destroy_tool_calls_owned(m.tool_calls)
	destroy_media_parts_owned(m.media)
}

destroy_messages :: proc(msgs: []Message) {
	for m in msgs {
		destroy_message(m)
	}
}

destroy_messages_owned :: proc(msgs: []Message) {
	destroy_messages(msgs)
	delete(msgs)
}

destroy_chat_response :: proc(res: ^Chat_Response) {
	delete(res.content)
	delete(res.reasoning)
	delete(res.model)
	delete(res.err)
	delete(res.finish_reason)
	destroy_tool_calls_owned(res.tool_calls)
	res^ = {}
}
