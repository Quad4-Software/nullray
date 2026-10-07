// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package provider

import "core:os"
import "core:strings"
import "core:testing"
import "nullray:constants"

@(private)
save_num_ctx_env :: proc() -> (saved: string, had: bool) {
	if v, ok := os.lookup_env(constants.ENV_OLLAMA_NUM_CTX, context.temp_allocator); ok {
		return strings.clone(v), true
	}
	return "", false
}

@(private)
restore_num_ctx_env :: proc(saved: string, had: bool) {
	if had {
		os.set_env(constants.ENV_OLLAMA_NUM_CTX, saved)
	} else {
		os.unset_env(constants.ENV_OLLAMA_NUM_CTX)
	}
	delete(saved)
}

@test
test_parse_ollama_show_full :: proc(t: ^testing.T) {
	body := `{
		"modelfile": "FROM x",
		"parameters": "stop EOS_TOKEN\nnum_ctx 4096\ntemperature 1.0\nnum_ctx 32768",
		"details": {"family": "gemma3", "parameter_size": "4.3B", "quantization_level": "Q4_K_M"},
		"model_info": {"gemma3.context_length": 131072, "gemma3.embedding_length": 2560, "general.architecture": "gemma3"},
		"capabilities": ["completion", "tools", "vision"]
	}`
	caps := parse_ollama_show_body(body)
	defer local_caps_destroy(&caps)
	testing.expect_value(t, caps.context_length, 131072)
	testing.expect_value(t, caps.modelfile_num_ctx, 32768)
	testing.expect_value(t, caps.parameter_size, "4.3B")
	testing.expect(t, caps.tools_known)
	testing.expect(t, caps.supports_tools)
	testing.expect(t, caps.supports_vision)
	testing.expect(t, !caps.supports_thinking)
}

@test
test_parse_ollama_show_no_capabilities :: proc(t: ^testing.T) {
	body := `{"model_info": {"qwen3.context_length": 8192, "tiny.context_length": 2048}}`
	caps := parse_ollama_show_body(body)
	defer local_caps_destroy(&caps)
	// Largest context_length wins across arch-prefixed keys.
	testing.expect_value(t, caps.context_length, 8192)
	testing.expect(t, !caps.tools_known)
	testing.expect(t, !caps.supports_tools)
	testing.expect_value(t, caps.parameter_size, "")
	testing.expect_value(t, caps.modelfile_num_ctx, 0)
}

@test
test_parse_ollama_show_empty_capabilities :: proc(t: ^testing.T) {
	caps := parse_ollama_show_body(`{"capabilities": []}`)
	defer local_caps_destroy(&caps)
	testing.expect(t, caps.tools_known)
	testing.expect(t, !caps.supports_tools)
}

@test
test_parse_modelfile_num_ctx_last_wins :: proc(t: ^testing.T) {
	testing.expect_value(t, parse_modelfile_num_ctx("num_ctx 2048\nnum_ctx 8192\n"), 8192)
	testing.expect_value(t, parse_modelfile_num_ctx("temperature 0.7\nstop EOS"), 0)
	testing.expect_value(t, parse_modelfile_num_ctx("num_ctx abc\nnum_ctx 4096"), 4096)
	testing.expect_value(t, parse_modelfile_num_ctx("num_ctx 16384   "), 16384)
	testing.expect_value(t, parse_modelfile_num_ctx(""), 0)
}

@test
test_parse_ollama_ps_context :: proc(t: ^testing.T) {
	body := `{"models": [
		{"name": "gemma3:4b", "model": "gemma3:4b", "size_vram": 3000000000, "context_length": 65536},
		{"name": "other:latest", "context_length": 4096}
	]}`
	testing.expect_value(t, parse_ollama_ps_context(body, "gemma3:4b"), 65536)
	testing.expect_value(t, parse_ollama_ps_context(body, "other:latest"), 4096)
	testing.expect_value(t, parse_ollama_ps_context(body, "missing:1b"), 0)
	testing.expect_value(t, parse_ollama_ps_context(body, ""), 65536)
	testing.expect_value(t, parse_ollama_ps_context(`{"models": []}`, "m"), 0)
	testing.expect_value(t, parse_ollama_ps_context(`not json`, "m"), 0)
}

@test
test_parse_llamacpp_props_tool_use :: proc(t: ^testing.T) {
	body := `{
		"total_slots": 2,
		"chat_template_tool_use": true,
		"default_generation_settings": {"n_ctx": 8192, "seed": -1, "params": {}},
		"model_alias": "local"
	}`
	caps := parse_llamacpp_props_body(body)
	defer local_caps_destroy(&caps)
	testing.expect_value(t, caps.total_slots, 2)
	testing.expect_value(t, caps.context_length, 8192)
	testing.expect(t, caps.tools_known)
	testing.expect(t, caps.supports_tools)
}

@test
test_parse_llamacpp_props_template_caps :: proc(t: ^testing.T) {
	body := `{
		"chat_template_caps": {"supports_tool_calls": false, "supports_object_tool_calls": false},
		"default_generation_settings": {"n_ctx": 4096}
	}`
	caps := parse_llamacpp_props_body(body)
	defer local_caps_destroy(&caps)
	testing.expect_value(t, caps.context_length, 4096)
	testing.expect(t, caps.tools_known)
	testing.expect(t, !caps.supports_tools)
}

@test
test_provider_supports_tools_flag :: proc(t: ^testing.T) {
	p := make_ollama("http://127.0.0.1:11434", "", "m")
	defer provider_destroy(&p)
	// Unknown capability data assumes tools rather than penalizing old servers.
	testing.expect(t, provider_supports_tools(&p))
	p.caps.tools_known = true
	p.caps.supports_tools = false
	testing.expect(t, !provider_supports_tools(&p))
	p.caps.supports_tools = true
	testing.expect(t, provider_supports_tools(&p))
}

@(private)
seeded_ollama :: proc(ctx_len, modelfile, loaded: int) -> Provider {
	p := make_ollama("http://127.0.0.1:11434", "", "m")
	p.caps.probed = true
	p.caps.probed_model = strings.clone("m")
	p.caps.context_length = ctx_len
	p.caps.modelfile_num_ctx = modelfile
	p.caps.loaded_ctx = loaded
	return p
}

@test
test_ollama_num_ctx_precedence :: proc(t: ^testing.T) {
	saved, had := save_num_ctx_env()
	defer restore_num_ctx_env(saved, had)
	os.unset_env(constants.ENV_OLLAMA_NUM_CTX)

	// context_length probed: min(trained window, 32k cap).
	p := seeded_ollama(131072, 0, 0)
	defer provider_destroy(&p)
	testing.expect_value(t, ollama_num_ctx(&p, "m"), 32768)

	// Modelfile num_ctx is explicit user config, honored as-is even when
	// smaller than the computed window.
	p.caps.modelfile_num_ctx = 8192
	testing.expect_value(t, ollama_num_ctx(&p, "m"), 8192)

	// A live window larger than the computed value is honored.
	p.caps.loaded_ctx = 65536
	testing.expect_value(t, ollama_num_ctx(&p, "m"), 65536)

	// A stale small live window never shrinks the computed value.
	p.caps.loaded_ctx = 4096
	testing.expect_value(t, ollama_num_ctx(&p, "m"), 8192)

	// Small trained window caps the auto value below the agent floor.
	local_caps_destroy(&p.caps)
	p.caps.probed = true
	p.caps.probed_model = strings.clone("m")
	p.caps.context_length = 8192
	testing.expect_value(t, ollama_num_ctx(&p, "m"), 8192)

	// Nothing probed: pin the agent floor instead of trusting the silent 4k default.
	local_caps_destroy(&p.caps)
	p.caps.probed = true
	p.caps.probed_model = strings.clone("m")
	testing.expect_value(t, ollama_num_ctx(&p, "m"), constants.OLLAMA_MIN_AGENT_CTX)

	// Env override wins outright, <=0 opts out of sending the field.
	os.set_env(constants.ENV_OLLAMA_NUM_CTX, "48000")
	testing.expect_value(t, ollama_num_ctx(&p, "m"), 48000)
	os.set_env(constants.ENV_OLLAMA_NUM_CTX, "0")
	testing.expect_value(t, ollama_num_ctx(&p, "m"), 0)
}

@test
test_ollama_num_ctx_written_to_body :: proc(t: ^testing.T) {
	saved, had := save_num_ctx_env()
	defer restore_num_ctx_env(saved, had)
	os.unset_env(constants.ENV_OLLAMA_NUM_CTX)

	p := seeded_ollama(131072, 0, 0)
	defer provider_destroy(&p)
	msgs := []Message{{role = .User, content = "hi"}}
	body := build_openai_chat_body(&p, Chat_Request{messages = msgs}, "m", false, nil)
	testing.expect(t, strings.contains(body, `"num_ctx":32768`))
	testing.expect(t, strings.contains(body, `"options":{"num_ctx":32768}`))
}
