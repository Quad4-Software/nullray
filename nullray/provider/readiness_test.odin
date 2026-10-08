// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package provider

import "core:testing"

@(test)
test_provider_readiness_label_key_and_base :: proc(t: ^testing.T) {
	orouter := Provider{id = "openrouter", name = "OpenRouter", api_key = "", base_url = "https://openrouter.ai/api/v1"}
	testing.expect_value(t, provider_readiness_label(&orouter, false), "no key")
	orouter.api_key = "sk-or-test"
	testing.expect_value(t, provider_readiness_label(&orouter, false), "configured")
	testing.expect(t, provider_is_ready(&orouter, false))

	fw := Provider{id = "fireworks", name = "Fireworks", api_key = "k", base_url = "https://api.fireworks.ai/inference/v1"}
	testing.expect_value(t, provider_readiness_label(&fw, false), "configured")

	compat := Provider{id = "openai-compat", name = "Compat", api_key = "", base_url = ""}
	testing.expect_value(t, provider_readiness_label(&compat, false), "no base")
	compat.base_url = "http://127.0.0.1:8000/v1"
	testing.expect_value(t, provider_readiness_label(&compat, false), "configured")

	local := Provider{id = "ollama", name = "Ollama"}
	testing.expect_value(t, provider_readiness_label(&local, false), "local")
}

@(test)
test_provider_is_local :: proc(t: ^testing.T) {
	testing.expect(t, provider_is_local("ollama"))
	testing.expect(t, provider_is_local("lmstudio"))
	testing.expect(t, provider_is_local("llamacpp"))
	testing.expect(t, !provider_is_local("openrouter"))
	testing.expect(t, !provider_is_local("openai-compat"))
	testing.expect(t, !provider_is_local("fireworks"))
}

@(test)
test_provider_ids_cover_registry_builtins :: proc(t: ^testing.T) {
	testing.expect_value(t, len(PROVIDER_IDS), 8)
	want := []string{
		"ollama",
		"lmstudio",
		"llamacpp",
		"openai-compat",
		"openrouter",
		"opencode",
		"opencode-go",
		"fireworks",
	}
	for id in want {
		found := false
		for have in PROVIDER_IDS {
			if have == id {
				found = true
				break
			}
		}
		testing.expect(t, found)
	}
}

@(test)
test_normalize_provider_aliases :: proc(t: ^testing.T) {
	testing.expect_value(t, normalize_provider_id("oai"), "openai-compat")
	testing.expect_value(t, normalize_provider_id("custom"), "openai-compat")
	testing.expect_value(t, normalize_provider_id("zen"), "opencode")
	testing.expect_value(t, normalize_provider_id("llama.cpp"), "llamacpp")
	testing.expect_value(t, normalize_provider_id("fw"), "fireworks")
}
