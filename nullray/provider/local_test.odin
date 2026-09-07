package provider

import "core:os"
import "core:testing"
import "nullray:constants"

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
test_make_ollama_list_hook :: proc(t: ^testing.T) {
	p := make_ollama()
	defer provider_destroy(&p)
	testing.expect_value(t, p.id, "ollama")
	testing.expect(t, p.list_models != nil)
}
