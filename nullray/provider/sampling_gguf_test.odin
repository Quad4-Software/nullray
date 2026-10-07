// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package provider

import "core:os"
import "core:strings"
import "core:testing"
import "nullray:constants"

@(test)
test_gguf_sampling_applies :: proc(t: ^testing.T) {
	os.unset_env(constants.ENV_GGUF_SAMPLE)
	testing.expect(t, gguf_sampling_applies("llamacpp", "qwen", `[{"type":"function"}]`))
	testing.expect(t, gguf_sampling_applies("ollama", "llama3", `[{"type":"function"}]`))
	testing.expect(t, !gguf_sampling_applies("ollama", "llama3", ""))
	testing.expect(t, !gguf_sampling_applies("openai", "gpt-4", `[{"type":"function"}]`))
	testing.expect(t, gguf_sampling_applies("openai-compat", "model.gguf", `[{"type":"function"}]`))
	os.set_env(constants.ENV_GGUF_SAMPLE, "0")
	defer os.unset_env(constants.ENV_GGUF_SAMPLE)
	testing.expect(t, !gguf_sampling_applies("llamacpp", "qwen", `[{"type":"function"}]`))
}

@(test)
test_apply_gguf_tool_sampling_clamps :: proc(t: ^testing.T) {
	os.unset_env(constants.ENV_GGUF_SAMPLE)
	req := Chat_Request{temperature = 0.8, temperature_set = true}
	apply_gguf_tool_sampling(&req, "llamacpp", "qwen", `[{"type":"function"}]`)
	testing.expect_value(t, req.temperature, constants.GGUF_TOOL_TEMP)
	testing.expect(t, req.temperature_set)
	testing.expect(t, req.repetition_penalty_set)
	testing.expect_value(t, req.repetition_penalty, constants.GGUF_TOOL_REP_PENALTY)

	req2 := Chat_Request{temperature = 0.1, temperature_set = true}
	apply_gguf_tool_sampling(&req2, "llamacpp", "qwen", `[{"type":"function"}]`)
	testing.expect_value(t, req2.temperature, 0.1)

	req3 := Chat_Request{}
	apply_gguf_tool_sampling(&req3, "openai", "gpt", `[{"type":"function"}]`)
	testing.expect(t, !req3.temperature_set)
}

@(test)
test_quant_family_detect :: proc(t: ^testing.T) {
	testing.expect(t, quant_family_detect("llama-3.1-8b-instruct") == .Llama)
	testing.expect(t, quant_family_detect("Meta-Llama-3-8B") == .Llama)
	testing.expect(t, quant_family_detect("codellama-7b-q4_k_m.gguf") == .Llama)
	testing.expect(t, quant_family_detect("ollama/llama3.2:3b") == .Llama)
	// The provider name ollama embeds llama and must not win the match.
	testing.expect(t, quant_family_detect("ollama/qwen3:8b") == .Qwen)
	testing.expect(t, quant_family_detect("qwen2.5-coder-7b") == .Qwen)
	testing.expect(t, quant_family_detect("mistral-7b-instruct") == .Unset)
	testing.expect(t, quant_family_detect("") == .Unset)
}

@(test)
test_quant_rank_and_tier :: proc(t: ^testing.T) {
	testing.expect_value(t, quant_rank("llama-3.1-8b-q4_k_m.gguf"), 4)
	testing.expect_value(t, quant_rank("model-Q8_0.gguf"), 8)
	testing.expect_value(t, quant_rank("model:Q6_K"), 6)
	testing.expect_value(t, quant_rank("model-iq3_xs.gguf"), 3)
	testing.expect_value(t, quant_rank("model-f16.gguf"), 16)
	testing.expect_value(t, quant_rank("model-bf16.gguf"), 16)
	testing.expect_value(t, quant_rank("model-f32.gguf"), 32)
	testing.expect_value(t, quant_rank("qwen3:8b"), -1)
	testing.expect_value(t, quant_rank("seq2seq-model"), -1)
	testing.expect(t, quant_tier_detect("x-q4_k_m") == .Low)
	testing.expect(t, quant_tier_detect("x-q2_k") == .Low)
	testing.expect(t, quant_tier_detect("x-q5_k_m") == .Mid)
	testing.expect(t, quant_tier_detect("x-q8_0") == .High)
	testing.expect(t, quant_tier_detect("qwen3") == .Unset)
}

@(test)
test_gguf_tool_temp_cap_matrix :: proc(t: ^testing.T) {
	// Llama at low quant gets the strict cap, all other combos keep default.
	testing.expect_value(t, gguf_tool_temp_cap_for(.Llama, .Low), GGUF_TOOL_TEMP_LLAMA_LOW)
	testing.expect_value(t, gguf_tool_temp_cap_for(.Llama, .Mid), f64(constants.GGUF_TOOL_TEMP))
	testing.expect_value(t, gguf_tool_temp_cap_for(.Llama, .High), f64(constants.GGUF_TOOL_TEMP))
	testing.expect_value(t, gguf_tool_temp_cap_for(.Llama, .Unset), f64(constants.GGUF_TOOL_TEMP))
	testing.expect_value(t, gguf_tool_temp_cap_for(.Qwen, .Low), f64(constants.GGUF_TOOL_TEMP))
	testing.expect_value(t, gguf_tool_temp_cap_for(.Qwen, .High), f64(constants.GGUF_TOOL_TEMP))
	testing.expect_value(t, gguf_tool_temp_cap_for(.Unset, .Low), f64(constants.GGUF_TOOL_TEMP))
	testing.expect_value(t, gguf_tool_temp_cap_for(.Unset, .Unset), f64(constants.GGUF_TOOL_TEMP))
}

@(test)
test_quant_resolve_sniffed :: proc(t: ^testing.T) {
	// Pure resolver path, no profile table involved. Foreign installed
	// profiles without quant fields cannot change these outcomes.
	f1, t1 := quant_resolve(.Unset, .Unset, "llama-3.1-8b-q4_k_m.gguf")
	testing.expect(t, f1 == .Llama && t1 == .Low)
	testing.expect_value(t, gguf_tool_temp_cap_for(f1, t1), GGUF_TOOL_TEMP_LLAMA_LOW)

	f2, t2 := quant_resolve(.Unset, .Unset, "llama-3.1-8b-q8_0.gguf")
	testing.expect(t, f2 == .Llama && t2 == .High)
	testing.expect_value(t, gguf_tool_temp_cap_for(f2, t2), f64(constants.GGUF_TOOL_TEMP))

	f3, t3 := quant_resolve(.Unset, .Unset, "qwen3-7b-q4_k_m.gguf")
	testing.expect(t, f3 == .Qwen && t3 == .Low)
	testing.expect_value(t, gguf_tool_temp_cap_for(f3, t3), f64(constants.GGUF_TOOL_TEMP))

	// No quant tag means unset tier, so the default cap applies.
	_, t4 := quant_resolve(.Unset, .Unset, "llama-3.1-8b")
	testing.expect(t, t4 == .Unset)

	// Profile fields win over filename sniffing.
	f5, t5 := quant_resolve(.Llama, .High, "safe-llama-q4_k_m.gguf")
	testing.expect(t, f5 == .Llama && t5 == .High)
	testing.expect_value(t, gguf_tool_temp_cap_for(f5, t5), f64(constants.GGUF_TOOL_TEMP))
}

@(test)
test_apply_gguf_tool_sampling_llama_low :: proc(t: ^testing.T) {
	// End to end through the request path: llama at low quant clamps harder.
	os.unset_env(constants.ENV_GGUF_SAMPLE)
	req := Chat_Request{temperature = 0.8, temperature_set = true}
	apply_gguf_tool_sampling(&req, "llamacpp", "llama-3.1-8b-q4_k_m.gguf", `[{"type":"function"}]`)
	testing.expect_value(t, req.temperature, GGUF_TOOL_TEMP_LLAMA_LOW)
}

@(test)
test_write_repeat_penalty_json :: proc(t: ^testing.T) {
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	p := Provider{id = "llamacpp"}
	req := Chat_Request{repetition_penalty = 1, repetition_penalty_set = true}
	write_repeat_penalty_json(&b, &p, req)
	testing.expect(t, strings.contains(strings.to_string(b), `"repeat_penalty":1`))
}
