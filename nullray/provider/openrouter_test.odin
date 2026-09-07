package provider

import "core:testing"

@(test)
test_openrouter_credits_parse :: proc(t: ^testing.T) {
	out: OpenRouter_Balance
	parse_openrouter_credits_body(`{"data":{"total_credits":100.5,"total_usage":25.75}}`, &out)
	testing.expect(t, out.has_account)
	testing.expect(t, out.total_credits > 100.0)
	testing.expect(t, out.total_usage > 25.0)
}

@(test)
test_openrouter_key_parse :: proc(t: ^testing.T) {
	out: OpenRouter_Balance
	parse_openrouter_key_body(`{"data":{"limit":5,"limit_remaining":4.2}}`, &out)
	testing.expect(t, out.has_key_limit)
	testing.expect_value(t, out.key_limit, 5.0)
	testing.expect(t, out.key_limit_remaining > 4.0)
}
