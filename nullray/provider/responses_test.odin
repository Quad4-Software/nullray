// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package provider

import "core:encoding/json"
import "core:strings"
import "core:testing"

@(test)
test_responses_body_shapes :: proc(t: ^testing.T) {
	p := Provider{id = "opencode"}
	msgs := []Message{
		{role = .System, content = "sys prompt"},
		{role = .User, content = "hi"},
		{role = .Assistant, content = "", tool_calls = []Tool_Call{
			{id = "call_1", name = "read_file", arguments = `{"path":"a"}`},
		}},
		{role = .Tool, tool_call_id = "call_1", content = "file body"},
	}
	req := Chat_Request{
		model = "gpt-5.5",
		messages = msgs,
		max_tokens = 100,
		tools_json = `[{"type":"function","function":{"name":"read_file","description":"read","parameters":{"type":"object","properties":{"path":{"type":"string"}},"required":["path"]}}}]`,
		reasoning_effort = "high",
	}
	body := build_responses_body(&p, req, "gpt-5.5")

	doc, err := json.parse_string(body, .JSON, allocator = context.temp_allocator)
	testing.expect(t, err == .None)
	obj := doc.(json.Object)

	testing.expect(t, obj["model"].(json.String) == "gpt-5.5")
	testing.expect(t, obj["instructions"].(json.String) == "sys prompt")
	testing.expect(t, json_int_field(obj, "max_output_tokens") == 100)
	testing.expect(t, obj["store"].(json.Boolean) == false)

	in_arr := obj["input"].(json.Array)
	testing.expect_value(t, len(in_arr), 3)
	i0 := in_arr[0].(json.Object)
	testing.expect(t, i0["role"].(json.String) == "user")
	i1 := in_arr[1].(json.Object)
	testing.expect(t, i1["type"].(json.String) == "function_call")
	testing.expect(t, i1["call_id"].(json.String) == "call_1")
	i2 := in_arr[2].(json.Object)
	testing.expect(t, i2["type"].(json.String) == "function_call_output")
	testing.expect(t, i2["output"].(json.String) == "file body")

	tools := obj["tools"].(json.Array)
	testing.expect_value(t, len(tools), 1)
	t0 := tools[0].(json.Object)
	testing.expect(t, t0["type"].(json.String) == "function")
	testing.expect(t, t0["name"].(json.String) == "read_file")
	// flat shape: parameters sits beside name, not under function
	_, has_params := t0["parameters"]
	testing.expect(t, has_params)
	_, has_fn := t0["function"]
	testing.expect(t, !has_fn)

	reason := obj["reasoning"].(json.Object)
	testing.expect(t, reason["effort"].(json.String) == "high")
}

@(test)
test_responses_parse_tool_and_text :: proc(t: ^testing.T) {
	body := `{
		"id": "resp_1",
		"status": "completed",
		"model": "gpt-5.5",
		"output": [
			{"type": "reasoning", "summary": [{"type": "summary_text", "text": "thought"}]},
			{"type": "function_call", "call_id": "call_9", "name": "read_file", "arguments": "{\"path\":\"x\"}", "status": "completed"},
			{"type": "message", "role": "assistant", "content": [{"type": "output_text", "text": "done"}]}
		],
		"usage": {"input_tokens": 11, "output_tokens": 7, "total_tokens": 18,
			"output_tokens_details": {"reasoning_tokens": 3},
			"input_tokens_details": {"cached_tokens": 4}}
	}`
	res := parse_responses_response(body, context.temp_allocator)
	testing.expect(t, res.ok)
	testing.expect(t, res.model == "gpt-5.5")
	testing.expect(t, res.content == "done")
	testing.expect(t, res.reasoning == "thought")
	testing.expect_value(t, len(res.tool_calls), 1)
	testing.expect(t, res.tool_calls[0].id == "call_9")
	testing.expect(t, res.tool_calls[0].name == "read_file")
	testing.expect(t, res.tool_calls[0].arguments == `{"path":"x"}`)
	testing.expect_value(t, res.usage.prompt_tokens, 11)
	testing.expect_value(t, res.usage.completion_tokens, 7)
	testing.expect_value(t, res.usage.reasoning_tokens, 3)
	testing.expect_value(t, res.usage.cache_read_tokens, 4)
}

@(test)
test_responses_parse_error :: proc(t: ^testing.T) {
	body := `{"error": {"message": "model busy"}}`
	res := parse_responses_response(body, context.temp_allocator)
	testing.expect(t, !res.ok)
	testing.expect(t, res.err == "model busy")
}
