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

Message :: struct {
	role:         Role,
	content:      string,
	reasoning:    string,
	tool_call_id: string,
	tool_calls:   []Tool_Call,
	name:         string,
	cacheable:    bool,
}

Chat_Request :: struct {
	model:            string,
	messages:         []Message,
	stream:           bool,
	tools_json:       string,
	tool_choice:      string,
	reasoning_effort: string,
	max_tokens:       int,
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
	prompt_tokens:     int,
	completion_tokens: int,
	total_tokens:      int,
	reasoning_tokens:  int,
}

Model_Info :: struct {
	id:   string,
	name: string,
}

Provider :: struct {
	id:            string,
	name:          string,
	base_url:      string,
	api_key:       string,
	default_model: string,
	chat:          Chat_Proc,
	list_models:   List_Proc,
	user_data:     rawptr,
}

Chat_Proc :: #type proc(p: ^Provider, req: Chat_Request, allocator := context.allocator) -> Chat_Response
List_Proc :: #type proc(p: ^Provider, allocator := context.allocator) -> (models: []Model_Info, err: string)

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
	delete(calls)
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
	return out
}

destroy_message :: proc(m: Message) {
	delete(m.content)
	delete(m.reasoning)
	delete(m.tool_call_id)
	delete(m.name)
	destroy_tool_calls(m.tool_calls)
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
	destroy_tool_calls(res.tool_calls)
	res^ = {}
}
