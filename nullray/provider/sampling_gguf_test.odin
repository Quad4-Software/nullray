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
test_write_repeat_penalty_json :: proc(t: ^testing.T) {
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	p := Provider{id = "llamacpp"}
	req := Chat_Request{repetition_penalty = 1, repetition_penalty_set = true}
	write_repeat_penalty_json(&b, &p, req)
	testing.expect(t, strings.contains(strings.to_string(b), `"repeat_penalty":1`))
}
