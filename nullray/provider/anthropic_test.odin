// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package provider

import "core:encoding/json"
import "core:strings"
import "core:testing"

@(test)
test_anthropic_body_shapes :: proc(t: ^testing.T) {
	p := Provider{id = "anthropic"}
	msgs := []Message{
		{role = .System, content = "sys prompt"},
		{role = .User, content = "hi"},
		{role = .Assistant, content = "", tool_calls = []Tool_Call{
			{id = "call_1", name = "read_file", arguments = `{"path":"a"}`},
		}},
		{role = .Tool, tool_call_id = "call_1", content = "file body"},
		{role = .Tool, tool_call_id = "call_2", content = "second"},
	}
	req := Chat_Request{model = "claude-sonnet-5", messages = msgs, max_tokens = 100}
	body := build_anthropic_body(&p, req, "claude-sonnet-5", true)

	doc, err := json.parse_string(body, .JSON, allocator = context.temp_allocator)
	testing.expect(t, err == .None)
	obj := doc.(json.Object)

	testing.expect(t, json_int_field(obj, "max_tokens") == 100)
	testing.expect(t, obj["stream"].(json.Boolean) == true)

	sys := obj["system"].(json.Array)
	testing.expect_value(t, len(sys), 1)

	arr := obj["messages"].(json.Array)
	// user, assistant(tool_use), merged tool_result user
	testing.expect_value(t, len(arr), 3)
	m0 := arr[0].(json.Object)
	testing.expect(t, m0["role"].(json.String) == "user")
	m1 := arr[1].(json.Object)
	testing.expect(t, m1["role"].(json.String) == "assistant")
	blocks := m1["content"].(json.Array)
	testing.expect_value(t, len(blocks), 1)
	testing.expect(t, blocks[0].(json.Object)["type"].(json.String) == "tool_use")
	testing.expect(t, blocks[0].(json.Object)["name"].(json.String) == "read_file")
	m2 := arr[2].(json.Object)
	results := m2["content"].(json.Array)
	testing.expect_value(t, len(results), 2)
	testing.expect(t, results[0].(json.Object)["type"].(json.String) == "tool_result")
	testing.expect(t, results[0].(json.Object)["tool_use_id"].(json.String) == "call_1")
	_, has_err := results[0].(json.Object)["is_error"]
	testing.expect(t, !has_err)
}

@(test)
test_anthropic_tool_result_is_error :: proc(t: ^testing.T) {
	p := Provider{id = "anthropic"}
	msgs := []Message{
		{role = .User, content = "hi"},
		{role = .Assistant, content = "", tool_calls = []Tool_Call{
			{id = "call_1", name = "read_file", arguments = `{"path":"a"}`},
		}},
		{role = .Tool, tool_call_id = "call_1", content = "not found", is_error = true},
	}
	req := Chat_Request{model = "claude-sonnet-5", messages = msgs, max_tokens = 100}
	body := build_anthropic_body(&p, req, "claude-sonnet-5", false)
	doc, err := json.parse_string(body, .JSON, allocator = context.temp_allocator)
	testing.expect(t, err == .None)
	arr := doc.(json.Object)["messages"].(json.Array)
	results := arr[2].(json.Object)["content"].(json.Array)
	block := results[0].(json.Object)
	testing.expect(t, block["type"].(json.String) == "tool_result")
	testing.expect(t, block["is_error"].(json.Boolean) == true)
}

@(test)
test_anthropic_body_tools_and_thinking :: proc(t: ^testing.T) {
	p := Provider{id = "anthropic"}
	msgs := []Message{{role = .User, content = "hi"}}
	req := Chat_Request{
		model = "claude-opus-5",
		messages = msgs,
		max_tokens = 500,
		reasoning_effort = "low",
		tools_json = `[{"type":"function","function":{"name":"ls","description":"list","parameters":{"type":"object","properties":{"p":{"type":"string"}}}}}]`,
		tool_choice = "required",
		temperature = 0.5,
		temperature_set = true,
	}
	body := build_anthropic_body(&p, req, "claude-opus-5", false)
	doc, err := json.parse_string(body, .JSON, allocator = context.temp_allocator)
	testing.expect(t, err == .None)
	obj := doc.(json.Object)

	tools := obj["tools"].(json.Array)
	testing.expect_value(t, len(tools), 1)
	t0 := tools[0].(json.Object)
	testing.expect(t, t0["name"].(json.String) == "ls")
	testing.expect(t, t0["input_schema"].(json.Object)["type"].(json.String) == "object")
	testing.expect(t, obj["tool_choice"].(json.Object)["type"].(json.String) == "any")

	th := obj["thinking"].(json.Object)
	testing.expect(t, th["type"].(json.String) == "enabled")
	budget := json_int_field(th, "budget_tokens")
	testing.expect(t, budget == 4096)
	// thinking bumps max_tokens above the budget
	testing.expect(t, json_int_field(obj, "max_tokens") > budget)
	// sampling is dropped while thinking is on
	_, has_temp := obj["temperature"]
	testing.expect(t, !has_temp)
}

@(test)
test_anthropic_parse_response :: proc(t: ^testing.T) {
	body := `{"id":"msg_1","type":"message","role":"assistant","model":"claude-sonnet-5","content":[{"type":"thinking","thinking":"ponder"},{"type":"text","text":"answer "},{"type":"text","text":"here"},{"type":"tool_use","id":"toolu_9","name":"run","input":{"cmd":"ls"}}],"stop_reason":"tool_use","usage":{"input_tokens":10,"output_tokens":7,"cache_read_input_tokens":5}}`
	res := parse_anthropic_response(body)
	defer destroy_chat_response(&res)
	testing.expect(t, res.ok)
	testing.expect(t, res.content == "answer here")
	testing.expect(t, res.reasoning == "ponder")
	testing.expect(t, res.finish_reason == "tool_use")
	testing.expect_value(t, len(res.tool_calls), 1)
	testing.expect(t, res.tool_calls[0].name == "run")
	testing.expect(t, strings.contains(res.tool_calls[0].arguments, `"cmd"`))
	testing.expect_value(t, res.usage.prompt_tokens, 15)
	testing.expect_value(t, res.usage.completion_tokens, 7)
	testing.expect_value(t, res.usage.total_tokens, 22)
}

@(test)
test_anthropic_sse_blocks :: proc(t: ^testing.T) {
	accum: Stream_Accum
	strings.builder_init(&accum.content)
	strings.builder_init(&accum.reasoning)
	accum.tool_calls = make([dynamic]Tool_Call)
	accum.tool_sealed = make([dynamic]bool)
	accum.block_tool = make([dynamic]int)
	accum.ok = true
	defer stream_accum_reset(&accum)

	lines := []string{
		`data: {"type":"message_start","message":{"model":"claude-sonnet-5","usage":{"input_tokens":12,"output_tokens":1}}}`,
		`data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}`,
		`data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"hmm"}}`,
		`data: {"type":"content_block_stop","index":0}`,
		`data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_1","name":"read_file","input":{}}}`,
		`data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"path\":"}}`,
		`data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"\"a\"}"}}`,
		`data: {"type":"content_block_stop","index":1}`,
		`data: {"type":"content_block_start","index":2,"content_block":{"type":"text","text":""}}`,
		`data: {"type":"content_block_delta","index":2,"delta":{"type":"text_delta","text":"done"}}`,
		`data: {"type":"content_block_stop","index":2}`,
		`data: {"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{"output_tokens":9}}`,
	}
	for l in lines {
		anthropic_sse_line_cb(l, &accum)
	}
	testing.expect(t, strings.to_string(accum.content) == "done")
	testing.expect(t, strings.to_string(accum.reasoning) == "hmm")
	testing.expect_value(t, len(accum.tool_calls), 1)
	testing.expect(t, accum.tool_calls[0].id == "toolu_1")
	testing.expect(t, accum.tool_calls[0].name == "read_file")
	testing.expect(t, accum.tool_calls[0].arguments == `{"path":"a"}`)
	testing.expect(t, accum.tool_sealed[0])
	testing.expect(t, accum.finish == "tool_use")
	testing.expect(t, accum.model == "claude-sonnet-5")
	testing.expect_value(t, accum.usage.prompt_tokens, 12)
	testing.expect_value(t, accum.usage.completion_tokens, 9)
}

@(test)
test_anthropic_headers_use_x_api_key :: proc(t: ^testing.T) {
	// OpenCode Messages still uses x-api-key; the dropped anthropic vendor
	// provider no longer exists, so this asserts the OpenCode path.
	p := Provider{id = "opencode", api_key = "sk-oc-test"}
	headers := make([dynamic]string, context.temp_allocator)
	anthropic_request_headers(&headers, &p)
	found_key, found_bearer, found_ver := false, false, false
	for h in headers {
		if h == "x-api-key: sk-oc-test" {
			found_key = true
		}
		if strings.has_prefix(h, "Authorization:") {
			found_bearer = true
		}
		if strings.has_prefix(h, "anthropic-version:") {
			found_ver = true
		}
	}
	testing.expect(t, found_key)
	testing.expect(t, !found_bearer)
	testing.expect(t, found_ver)
}
