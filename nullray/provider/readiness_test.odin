// SPDX-License-Identifier: 0BSD
package provider

import "core:testing"

@(test)
test_provider_readiness_label_key_and_base :: proc(t: ^testing.T) {
	openai := Provider{id = "openai", name = "OpenAI", api_key = "", base_url = "https://api.openai.com/v1"}
	testing.expect_value(t, provider_readiness_label(&openai, false), "no key")
	openai.api_key = "sk-test"
	testing.expect_value(t, provider_readiness_label(&openai, false), "configured")
	testing.expect(t, provider_is_ready(&openai, false))

	azure := Provider{id = "azure", name = "Azure", api_key = "k", base_url = ""}
	testing.expect_value(t, provider_readiness_label(&azure, false), "no base")
	testing.expect(t, !provider_is_ready(&azure, false))
	azure.base_url = "https://example.openai.azure.com"
	azure.api_key = ""
	testing.expect_value(t, provider_readiness_label(&azure, false), "no key")
	azure.api_key = "k"
	testing.expect_value(t, provider_readiness_label(&azure, false), "configured")

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
	testing.expect(t, !provider_is_local("openai"))
	testing.expect(t, !provider_is_local("openrouter"))
	testing.expect(t, !provider_is_local("openai-compat"))
}

@(test)
test_provider_ids_cover_registry_builtins :: proc(t: ^testing.T) {
	testing.expect(t, len(PROVIDER_IDS) >= 20)
	found_dash := false
	found_cerebras := false
	for id in PROVIDER_IDS {
		if id == "dashscope" {
			found_dash = true
		}
		if id == "cerebras" {
			found_cerebras = true
		}
	}
	testing.expect(t, found_dash)
	testing.expect(t, found_cerebras)
	found_llama := false
	for id in PROVIDER_IDS {
		if id == "llamacpp" {
			found_llama = true
		}
	}
	testing.expect(t, found_llama)
}
