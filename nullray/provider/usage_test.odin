package provider

import "core:encoding/json"
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
test_parse_usage_alt_names :: proc(t: ^testing.T) {
	doc, err := json.parse_string(`{"input_tokens":8,"output_tokens":2}`, .JSON)
	testing.expect(t, err == .None)
	u := parse_usage_value(doc)
	testing.expect_value(t, u.prompt_tokens, 8)
	testing.expect_value(t, u.completion_tokens, 2)
	testing.expect_value(t, u.total_tokens, 10)
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
