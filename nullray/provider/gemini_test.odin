// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package provider

import "core:encoding/json"
import "core:strings"
import "core:testing"

@(test)
test_gemini_body_shapes :: proc(t: ^testing.T) {
	p := Provider{id = "opencode"}
	msgs := []Message{
		{role = .System, content = "sys prompt"},
		{role = .User, content = "hi"},
		{role = .Assistant, content = "", tool_calls = []Tool_Call{
			{id = "gemini_fc_0", name = "read_file", arguments = `{"path":"a"}`},
		}},
		{role = .Tool, tool_call_id = "gemini_fc_0", name = "read_file", content = "file body"},
	}
	req := Chat_Request{
		model = "gemini-3.8-flash",
		messages = msgs,
		max_tokens = 100,
		tools_json = `[{"type":"function","function":{"name":"read_file","description":"read","parameters":{"type":"object","properties":{"path":{"type":"string"}},"required":["path"]}}}]`,
	}
	body := build_gemini_body(&p, req, "gemini-3.8-flash")

	doc, err := json.parse_string(body, .JSON, allocator = context.temp_allocator)
	testing.expect(t, err == .None)
	obj := doc.(json.Object)

	sys := obj["systemInstruction"].(json.Object)
	sys_parts := sys["parts"].(json.Array)
	testing.expect(t, sys_parts[0].(json.Object)["text"].(json.String) == "sys prompt")

	contents := obj["contents"].(json.Array)
	testing.expect_value(t, len(contents), 3)
	c0 := contents[0].(json.Object)
	testing.expect(t, c0["role"].(json.String) == "user")
	c1 := contents[1].(json.Object)
	testing.expect(t, c1["role"].(json.String) == "model")
	c1_parts := c1["parts"].(json.Array)
	fc := c1_parts[0].(json.Object)["functionCall"].(json.Object)
	testing.expect(t, fc["name"].(json.String) == "read_file")
	fc_args := fc["args"].(json.Object)
	testing.expect(t, fc_args["path"].(json.String) == "a")
	c2 := contents[2].(json.Object)
	c2_parts := c2["parts"].(json.Array)
	fr := c2_parts[0].(json.Object)["functionResponse"].(json.Object)
	testing.expect(t, fr["name"].(json.String) == "read_file")
	fr_resp := fr["response"].(json.Object)
	testing.expect(t, fr_resp["result"].(json.String) == "file body")

	tools := obj["tools"].(json.Array)
	decls := tools[0].(json.Object)["functionDeclarations"].(json.Array)
	testing.expect_value(t, len(decls), 1)
	testing.expect(t, decls[0].(json.Object)["name"].(json.String) == "read_file")

	gc := obj["generationConfig"].(json.Object)
	testing.expect(t, json_int_field(gc, "maxOutputTokens") == 100)
}

@(test)
test_gemini_parse_calls_and_usage :: proc(t: ^testing.T) {
	body := `{
		"candidates": [{
			"content": {"role": "model", "parts": [
				{"text": "let me look", "thought": true},
				{"functionCall": {"name": "read_file", "args": {"path": "x"}}},
				{"text": "done"}
			]},
			"finishReason": "STOP"
		}],
		"usageMetadata": {"promptTokenCount": 9, "candidatesTokenCount": 5, "totalTokenCount": 14, "thoughtsTokenCount": 2},
		"modelVersion": "gemini-3.8-flash"
	}`
	res := parse_gemini_response(body, context.temp_allocator)
	testing.expect(t, res.ok)
	testing.expect(t, res.content == "done")
	testing.expect(t, res.reasoning == "let me look")
	testing.expect_value(t, len(res.tool_calls), 1)
	testing.expect(t, res.tool_calls[0].name == "read_file")
	testing.expect(t, res.tool_calls[0].arguments == `{"path":"x"}`)
	testing.expect_value(t, res.usage.prompt_tokens, 9)
	testing.expect_value(t, res.usage.completion_tokens, 5)
	testing.expect_value(t, res.usage.reasoning_tokens, 2)
	testing.expect(t, res.finish_reason == "STOP")
	testing.expect(t, res.model == "gemini-3.8-flash")
}

@(test)
test_gemini_parse_error_and_block :: proc(t: ^testing.T) {
	err_body := `{"error": {"message": "overloaded"}}`
	res := parse_gemini_response(err_body, context.temp_allocator)
	testing.expect(t, !res.ok)
	testing.expect(t, res.err == "overloaded")

	blocked := `{"promptFeedback": {"blockReason": "SAFETY"}}`
	res2 := parse_gemini_response(blocked, context.temp_allocator)
	testing.expect(t, !res2.ok)
	testing.expect(t, strings.contains(res2.err, "SAFETY"))
}
