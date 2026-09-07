// SPDX-License-Identifier: 0BSD
package provider

import "core:strings"
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
test_openrouter_rate_limit_providers :: proc(t: ^testing.T) {
	body := `{"error":{"message":"Provider returned error","code":429,"metadata":{"provider_name":"DeepInfra","previous_errors":[{"provider_name":"Fireworks"},{"provider_name":"Venice"}]}}}`
	names := extract_openrouter_rate_limit_providers(body, context.allocator)
	defer {
		for n in names {
			delete(n)
		}
		delete(names)
	}
	testing.expect_value(t, len(names), 3)
	testing.expect_value(t, names[0], "DeepInfra")
	testing.expect_value(t, names[1], "Fireworks")
	testing.expect_value(t, names[2], "Venice")
}

@(test)
test_openrouter_extras_json :: proc(t: ^testing.T) {
	b: strings.Builder
	strings.builder_init(&b, context.allocator)
	defer strings.builder_destroy(&b)
	write_openrouter_extras(&b, []string{"DeepInfra", "Fireworks"})
	s := strings.to_string(b)
	testing.expect(t, strings.contains(s, `"allow_fallbacks":true`))
	testing.expect(t, strings.contains(s, `"DeepInfra"`))
	testing.expect(t, strings.contains(s, `"Fireworks"`))
}
