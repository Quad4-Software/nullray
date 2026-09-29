// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
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

@(test)
test_opencode_model_api_routing :: proc(t: ^testing.T) {
	testing.expect(t, opencode_model_api("opencode", "claude-opus-5") == .Messages)
	testing.expect(t, opencode_model_api("opencode", "claude-fable-5-1") == .Messages)
	testing.expect(t, opencode_model_api("opencode", "qwen3.8-flash") == .Messages)
	testing.expect(t, opencode_model_api("opencode", "qwen3.5-plus") == .Messages)
	testing.expect(t, opencode_model_api("opencode", "qwen3.8-max") == .Chat)
	testing.expect(t, opencode_model_api("opencode", "gpt-5.5") == .Responses)
	testing.expect(t, opencode_model_api("opencode", "grok-4.7") == .Responses)
	testing.expect(t, opencode_model_api("opencode", "muse-spark-1.3") == .Responses)
	testing.expect(t, opencode_model_api("opencode", "gemini-3-flash") == .Gemini)
	testing.expect(t, opencode_model_api("opencode", "jev-1.13") == .SystemOne)
	testing.expect(t, opencode_model_api("opencode", "big-pickle") == .Chat)
	testing.expect(t, opencode_model_api("opencode", "kimi-k3") == .Chat)
	testing.expect(t, opencode_model_api("opencode", "minimax-m2.5") == .Chat)
	testing.expect(t, opencode_model_api("opencode", "deepseek-v4-pro") == .Chat)
}

@(test)
test_opencode_go_fallback_differs_from_zen :: proc(t: ^testing.T) {
	// Without a catalog hit, Go serves qwen3.x over chat/completions while
	// minimax-m3 and qwen3.8-flash still ride messages.
	testing.expect(t, opencode_fallback_api("opencode-go", "qwen3.7-max") == .Chat)
	testing.expect(t, opencode_fallback_api("opencode-go", "qwen3.5-plus") == .Chat)
	testing.expect(t, opencode_fallback_api("opencode-go", "minimax-m3") == .Messages)
	testing.expect(t, opencode_fallback_api("opencode-go", "qwen3.8-flash") == .Messages)
	testing.expect(t, opencode_fallback_api("opencode", "qwen3.7-max") == .Messages)
}

@(test)
test_opencode_chat_rejects_unsupported_surface :: proc(t: ^testing.T) {
	p := Provider{id = "opencode", base_url = "https://opencode.ai/zen/v1"}
	req := Chat_Request{model = "gpt-5.5", messages = []Message{{role = .User, content = "hi"}}}
	res := opencode_chat(&p, req)
	defer destroy_chat_response(&res)
	testing.expect(t, !res.ok)
	testing.expect(t, strings.contains(res.err, "responses"))
}

@(test)
test_opencode_custom_base_bypasses_routing :: proc(t: ^testing.T) {
	// A proxied base may normalize all models to chat/completions, so the
	// unsupported-surface early exit must not fire there.
	p := Provider{id = "opencode", base_url = "http://127.0.0.1:1/v1"}
	req := Chat_Request{model = "gpt-5.5", messages = []Message{{role = .User, content = "hi"}}}
	res := opencode_chat(&p, req)
	defer destroy_chat_response(&res)
	testing.expect(t, !res.ok)
	testing.expect(t, !strings.contains(res.err, "does not support yet"))
}

@(test)
test_opencode_api_label :: proc(t: ^testing.T) {
	testing.expect(t, opencode_api_label("opencode", "claude-sonnet-5") == "messages")
	testing.expect(t, opencode_api_label("opencode", "gpt-5.5") == "responses")
	testing.expect(t, opencode_api_label("opencode", "gemini-3-flash") == "gemini")
	testing.expect(t, opencode_api_label("opencode", "kimi-k3") == "")
}

@(test)
test_ollama_origin_header :: proc(t: ^testing.T) {
	p := Provider{id = "ollama"}
	headers := make([dynamic]string, context.temp_allocator)
	append_provider_headers(&headers, &p)
	found := false
	for h in headers {
		if h == "Origin: http://127.0.0.1" {
			found = true
		}
	}
	testing.expect(t, found)
}
