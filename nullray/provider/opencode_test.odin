// SPDX-License-Identifier: 0BSD
package provider

import "core:strings"
import "core:testing"

@(test)
test_opencode_session_header :: proc(t: ^testing.T) {
	clear_session()
	defer clear_session()
	set_session("chat-42")

	p := Provider{id = "opencode-go"}
	headers := make([dynamic]string, context.temp_allocator)
	append_provider_headers(&headers, &p)

	found := false
	for h in headers {
		if strings.has_prefix(h, "x-opencode-session: ") {
			testing.expect_value(t, h, "x-opencode-session: chat-42")
			found = true
		}
	}
	testing.expect(t, found)
}

@(test)
test_opencode_session_fallback_when_unset :: proc(t: ^testing.T) {
	clear_session()
	defer clear_session()

	p := Provider{id = "opencode"}
	headers := make([dynamic]string, context.temp_allocator)
	append_provider_headers(&headers, &p)

	found := false
	for h in headers {
		if strings.has_prefix(h, "x-opencode-session: ") {
			testing.expect(t, len(h) > len("x-opencode-session: "))
			found = true
		}
	}
	testing.expect(t, found)
}

@(test)
test_opencode_header_skipped_for_other_providers :: proc(t: ^testing.T) {
	clear_session()
	defer clear_session()
	set_session("chat-42")

	p := Provider{id = "openrouter"}
	headers := make([dynamic]string, context.temp_allocator)
	append_provider_headers(&headers, &p)

	for h in headers {
		testing.expect(t, !strings.has_prefix(h, "x-opencode-session:"))
	}
}
