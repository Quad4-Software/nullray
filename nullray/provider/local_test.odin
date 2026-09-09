// SPDX-License-Identifier: 0BSD
package provider

import "core:os"
import "core:testing"
import "nullray:constants"

@(test)
test_parse_openai_models_reasoning_meta :: proc(t: ^testing.T) {
	body := `{"data":[{"id":"google/gemini-flash","reasoning":{"supported_efforts":["high","medium","low"],"default_effort":"medium","default_enabled":true,"mandatory":true}},{"id":"plain/model"}]}`
	models, err := parse_openai_models_body(body)
	testing.expect_value(t, err, "")
	testing.expect_value(t, len(models), 2)
	testing.expect(t, models[0].has_reasoning_meta)
	testing.expect_value(t, models[0].reasoning_default, "medium")
	testing.expect(t, models[0].reasoning_default_on)
	testing.expect(t, models[0].reasoning_mandatory)
	testing.expect_value(t, len(models[0].reasoning_efforts), 3)
	testing.expect_value(t, models[0].reasoning_efforts[0], "high")
	testing.expect(t, !models[1].has_reasoning_meta)
	destroy_models(models)
}

@(test)
test_parse_openai_models_body :: proc(t: ^testing.T) {
	body := `{"object":"list","data":[{"id":"gemma3:4b"},{"id":"llama3.2"}]}`
	models, err := parse_openai_models_body(body)
	testing.expect_value(t, err, "")
	testing.expect_value(t, len(models), 2)
	testing.expect_value(t, models[0].id, "gemma3:4b")
	testing.expect_value(t, models[1].id, "llama3.2")
	destroy_models(models)
}

@(test)
test_parse_ollama_tags_body :: proc(t: ^testing.T) {
	body := `{"models":[{"name":"gemma3:4b","model":"gemma3:4b"},{"name":"qwen2.5-coder:7b"}]}`
	models, err := parse_ollama_tags_body(body)
	testing.expect_value(t, err, "")
	testing.expect_value(t, len(models), 2)
	testing.expect_value(t, models[0].id, "gemma3:4b")
	testing.expect_value(t, models[1].id, "qwen2.5-coder:7b")
	destroy_models(models)
}

@(test)
test_openai_compat_root_strips_v1 :: proc(t: ^testing.T) {
	testing.expect_value(t, openai_compat_root("http://127.0.0.1:11434/v1"), "http://127.0.0.1:11434")
	testing.expect_value(t, openai_compat_root("http://127.0.0.1:11434/v1/"), "http://127.0.0.1:11434")
	testing.expect_value(t, openai_compat_root("http://127.0.0.1:11434"), "http://127.0.0.1:11434")
}

@(test)
test_normalize_openai_base :: proc(t: ^testing.T) {
	testing.expect_value(t, normalize_openai_base("http://127.0.0.1:11434"), "http://127.0.0.1:11434/v1")
	testing.expect_value(t, normalize_openai_base("http://127.0.0.1:1234/v1"), "http://127.0.0.1:1234/v1")
	testing.expect_value(t, normalize_openai_base("http://127.0.0.1:1234/"), "http://127.0.0.1:1234/v1")
}

@(test)
test_make_lmstudio_defaults :: proc(t: ^testing.T) {
	p := make_lmstudio("http://127.0.0.1:1234", "lm-studio", "local-model")
	defer provider_destroy(&p)
	testing.expect_value(t, p.id, "lmstudio")
	testing.expect_value(t, p.api_key, "lm-studio")
	testing.expect_value(t, p.base_url, "http://127.0.0.1:1234/v1")
	testing.expect(t, p.list_models != nil)
	if _, ok := os.lookup_env(constants.ENV_LMSTUDIO_KEY, context.temp_allocator); !ok {
		p2 := make_lmstudio()
		defer provider_destroy(&p2)
		testing.expect_value(t, p2.api_key, "lm-studio")
	}
}

@(test)
test_make_llamacpp_defaults :: proc(t: ^testing.T) {
	p := make_llamacpp("http://127.0.0.1:8080", "", "local")
	defer provider_destroy(&p)
	testing.expect_value(t, p.id, "llamacpp")
	testing.expect_value(t, p.name, "llama.cpp")
	testing.expect_value(t, p.base_url, "http://127.0.0.1:8080/v1")
	testing.expect_value(t, p.default_model, "local")
	testing.expect(t, p.list_models != nil)
	if _, ok := os.lookup_env(constants.ENV_LLAMACPP_HOST, context.temp_allocator); !ok {
		p2 := make_llamacpp()
		defer provider_destroy(&p2)
		testing.expect_value(t, p2.base_url, constants.DEFAULT_LLAMACPP_BASE)
	}
}

@(test)
test_normalize_provider_id_aliases :: proc(t: ^testing.T) {
	testing.expect_value(t, normalize_provider_id("OpenAI"), "openai")
	testing.expect_value(t, normalize_provider_id("openai_compatible"), "openai-compat")
	testing.expect_value(t, normalize_provider_id("custom"), "openai-compat")
	testing.expect_value(t, normalize_provider_id("oai"), "openai")
	testing.expect_value(t, normalize_provider_id("qwen"), "dashscope")
	testing.expect_value(t, normalize_provider_id("alibaba"), "dashscope")
	testing.expect_value(t, normalize_provider_id("nim"), "nvidia")
	testing.expect_value(t, normalize_provider_id("nvidia-nim"), "nvidia")
	testing.expect_value(t, normalize_provider_id("co"), "cohere")
	testing.expect_value(t, normalize_provider_id("llama.cpp"), "llamacpp")
	testing.expect_value(t, normalize_provider_id("llama-cpp"), "llamacpp")
	testing.expect_value(t, normalize_provider_id("llama"), "llamacpp")
	testing.expect_value(t, normalize_provider_id("lm-studio"), "lmstudio")
}

@(test)
test_local_probe_enabled_from_env :: proc(t: ^testing.T) {
	os.unset_env(constants.ENV_LOCAL_PROBE)
	defer os.unset_env(constants.ENV_LOCAL_PROBE)
	testing.expect(t, local_probe_enabled_from_env())
	os.set_env(constants.ENV_LOCAL_PROBE, "0")
	testing.expect(t, !local_probe_enabled_from_env())
	os.set_env(constants.ENV_LOCAL_PROBE, "off")
	testing.expect(t, !local_probe_enabled_from_env())
}

@(test)
test_provider_env_set :: proc(t: ^testing.T) {
	os.unset_env(constants.ENV_PROVIDER)
	defer os.unset_env(constants.ENV_PROVIDER)
	testing.expect(t, !provider_env_set())
	os.set_env(constants.ENV_PROVIDER, "ollama")
	testing.expect(t, provider_env_set())
	os.set_env(constants.ENV_PROVIDER, "  ")
	testing.expect(t, !provider_env_set())
}

@(test)
test_registry_auto_select_skips_when_env_set :: proc(t: ^testing.T) {
	os.set_env(constants.ENV_PROVIDER, "openrouter")
	defer os.unset_env(constants.ENV_PROVIDER)
	r: Registry
	registry_init(&r)
	defer registry_destroy(&r)
	testing.expect(t, !registry_auto_select_local(&r))
	p := registry_active(&r)
	testing.expect(t, p != nil)
	testing.expect_value(t, p.id, "openrouter")
}

@(test)
test_probe_local_provider_respects_disable :: proc(t: ^testing.T) {
	os.set_env(constants.ENV_LOCAL_PROBE, "0")
	defer os.unset_env(constants.ENV_LOCAL_PROBE)
	testing.expect(t, !probe_local_provider("ollama", 1))
}

@(test)
test_make_openai_defaults :: proc(t: ^testing.T) {
	p := make_openai("https://api.openai.com", "sk-test", "gpt-4o-mini")
	defer provider_destroy(&p)
	testing.expect_value(t, p.id, "openai")
	testing.expect_value(t, p.base_url, "https://api.openai.com/v1")
	testing.expect_value(t, p.api_key, "sk-test")
	testing.expect(t, uses_max_completion_tokens(&p, "gpt-4o-mini"))
}

@(test)
test_make_openai_compat_requires_base_shape :: proc(t: ^testing.T) {
	p := make_openai_compat("http://127.0.0.1:8080/v1", "tok", "local")
	defer provider_destroy(&p)
	testing.expect_value(t, p.id, "openai-compat")
	testing.expect_value(t, p.base_url, "http://127.0.0.1:8080/v1")
	testing.expect(t, !uses_max_completion_tokens(&p, "local"))
	testing.expect(t, uses_max_completion_tokens(&p, "o3-mini"))
}
