// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package provider

import "core:os"
import "core:strings"
import "core:testing"
import "nullray:constants"

@(test)
test_auth_kind_and_fallbacks :: proc(t: ^testing.T) {
	testing.expect(t, auth_kind_from_err("HTTP 401 unauthorized: User not found") == .Dead_Key)
	testing.expect(t, auth_is_failover_worthy("HTTP 401 unauthorized: User not found"))
	testing.expect(t, auth_kind_from_err("HTTP 402 payment required") == .Payment)
	testing.expect(t, !auth_is_failover_worthy("HTTP 500"))
	testing.expect(t, failover_why_from_err("HTTP 429 rate limited (retry later)") == .Rate_Limit)
	testing.expect(t, chat_is_failover_worthy("HTTP 429 rate limited (retry later)"))
	testing.expect(t, failover_why_from_err("timeout") == .Timeout)
	testing.expect(t, chat_is_failover_worthy("timeout"))
	testing.expect(t, failover_why_from_err("prompt exceeds context window") == .Context)
	testing.expect(t, chat_is_failover_worthy("n_ctx is too small: context size"))
	testing.expect(t, !chat_is_failover_worthy("HTTP 500"))
	testing.expect_value(t, failover_why_label(.Rate_Limit), "rate_limit")

	os.unset_env(constants.ENV_PROVIDER_FALLBACKS)
	testing.expect(t, len(provider_fallback_ids()) == 0)
	os.set_env(constants.ENV_PROVIDER_FALLBACKS, "ollama, groq,")
	defer os.unset_env(constants.ENV_PROVIDER_FALLBACKS)
	ids := provider_fallback_ids()
	testing.expect_value(t, len(ids), 2)
	testing.expect_value(t, ids[0], "ollama")
	testing.expect_value(t, ids[1], "groq")

	p, ok := make_provider_by_id("ollama")
	testing.expect(t, ok)
	testing.expect(t, provider_ready_for_chat(&p))
	provider_destroy(&p)
}

@(test)
test_credits_key_override :: proc(t: ^testing.T) {
	os.unset_env(constants.ENV_OPENROUTER_CREDITS_KEY)
	testing.expect_value(t, openrouter_credits_key("chat-key"), "chat-key")
	os.set_env(constants.ENV_OPENROUTER_CREDITS_KEY, "credits-only")
	defer os.unset_env(constants.ENV_OPENROUTER_CREDITS_KEY)
	testing.expect_value(t, openrouter_credits_key("chat-key"), "credits-only")
}
