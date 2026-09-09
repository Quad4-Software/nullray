// SPDX-License-Identifier: 0BSD
package provider

import "core:encoding/json"
import "core:strings"
import "core:testing"

@(test)
test_parse_usage_openai_shape :: proc(t: ^testing.T) {
	doc, err := json.parse_string(`{"prompt_tokens":10,"completion_tokens":4,"total_tokens":14}`, .JSON)
	testing.expect(t, err == .None)
	u := parse_usage_value(doc)
	testing.expect_value(t, u.prompt_tokens, 10)
	testing.expect_value(t, u.completion_tokens, 4)
	testing.expect_value(t, u.total_tokens, 14)
}

@(test)
test_parse_usage_empty_object :: proc(t: ^testing.T) {
	doc, err := json.parse_string(`{}`, .JSON)
	testing.expect(t, err == .None)
	u := parse_usage_value(doc)
	testing.expect_value(t, u.prompt_tokens, 0)
	testing.expect_value(t, u.completion_tokens, 0)
	testing.expect_value(t, u.total_tokens, 0)
}

@(test)
test_parse_openai_chat_bad_json :: proc(t: ^testing.T) {
	res := parse_openai_chat_response(`{broken`)
	defer destroy_chat_response(&res)
	testing.expect(t, !res.ok)
}

@(test)
test_parse_usage_alt_names :: proc(t: ^testing.T) {
	doc, err := json.parse_string(`{"input_tokens":8,"output_tokens":2}`, .JSON)
	testing.expect(t, err == .None)
	u := parse_usage_value(doc)
	testing.expect_value(t, u.prompt_tokens, 8)
	testing.expect_value(t, u.completion_tokens, 2)
	testing.expect_value(t, u.total_tokens, 10)
}

@(test)
test_parse_usage_with_cost :: proc(t: ^testing.T) {
	doc, err := json.parse_string(`{"prompt_tokens":10,"completion_tokens":4,"total_tokens":14,"cost":0.0012}`, .JSON)
	testing.expect(t, err == .None)
	u := parse_usage_value(doc)
	testing.expect_value(t, u.prompt_tokens, 10)
	testing.expect(t, u.cost_known)
	testing.expect(t, u.cost_usd > 0)
}

@(test)
test_destroy_messages_no_double_free :: proc(t: ^testing.T) {
	msgs := make([dynamic]Message)
	append(&msgs, Message{role = .User})
	append(&msgs, Message{role = .Assistant})
	destroy_messages(msgs[:])
	delete(msgs)
	testing.expect(t, true)
}

@(test)
test_parse_reasoning_content_field :: proc(t: ^testing.T) {
	body := `{"choices":[{"message":{"role":"assistant","content":"hi","reasoning_content":"think"},"finish_reason":"stop"}]}`
	res := parse_openai_chat_response(body)
	defer destroy_chat_response(&res)
	testing.expect(t, res.ok)
	testing.expect_value(t, res.content, "hi")
	testing.expect_value(t, res.reasoning, "think")
}

@(test)
test_write_sampling_json :: proc(t: ^testing.T) {
	b: strings.Builder
	strings.builder_init(&b)
	defer strings.builder_destroy(&b)
	p := Provider{id = "openrouter"}
	write_sampling_json(&b, &p, "google/gemini-2.5-flash", 0.7, 0.95, true, true)
	s := strings.to_string(b)
	testing.expect(t, strings.contains(s, `"temperature":0.7`))
	testing.expect(t, strings.contains(s, `"top_p":0.95`))

	strings.builder_reset(&b)
	write_sampling_json(&b, &p, "o3-mini", 0.9, 0.9, true, true)
	testing.expect_value(t, strings.to_string(b), "")
}

@(test)
test_write_reasoning_json_provider_shapes :: proc(t: ^testing.T) {
	b: strings.Builder
	strings.builder_init(&b)
	defer strings.builder_destroy(&b)

	or_p := Provider{id = "openrouter"}
	write_reasoning_json(&b, &or_p, "low")
	testing.expect(t, strings.contains(strings.to_string(b), `"reasoning":{"effort":"low"}`))

	strings.builder_reset(&b)
	co := Provider{id = "cohere"}
	write_reasoning_json(&b, &co, "low")
	testing.expect(t, strings.contains(strings.to_string(b), `"reasoning_effort":"high"`))

	strings.builder_reset(&b)
	ds := Provider{id = "deepseek"}
	write_reasoning_json(&b, &ds, "medium")
	s := strings.to_string(b)
	testing.expect(t, strings.contains(s, `"thinking":{"type":"enabled"}`))
	testing.expect(t, strings.contains(s, `"reasoning_effort":"high"`))

	strings.builder_reset(&b)
	dash := Provider{id = "dashscope"}
	write_reasoning_json(&b, &dash, "high")
	testing.expect(t, strings.contains(strings.to_string(b), `"enable_thinking":true`))

	strings.builder_reset(&b)
	ol := Provider{id = "ollama"}
	write_reasoning_json(&b, &ol, "low")
	testing.expect_value(t, strings.to_string(b), "")
}
