// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
GGUF and local-server sampling for tool-call turns.

Local GGUF backends (llama.cpp, Ollama, LM Studio, or a model id that
contains gguf) lose tool-call format accuracy above about 0.3 temperature.
On turns that ship a tools JSON we clamp temperature to 0.2 and pin
repeat_penalty to 1.0 (identity, no extra penalty). NULLRAY_GGUF_SAMPLE=0
disables the clamp.
*/

package provider

import "core:fmt"
import "core:os"
import "core:strings"
import "nullray:constants"

gguf_sampling_enabled :: proc() -> bool {
	if v, ok := os.lookup_env(constants.ENV_GGUF_SAMPLE, context.temp_allocator); ok {
		switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
		case "0", "false", "off", "no", "disable":
			return false
		}
	}
	return true
}

gguf_sampling_applies :: proc(provider_id, model, tools_json: string) -> bool {
	if !gguf_sampling_enabled() {
		return false
	}
	if len(strings.trim_space(tools_json)) == 0 {
		return false
	}
	if provider_is_local(provider_id) {
		return true
	}
	low := strings.to_lower(model, context.temp_allocator)
	return strings.contains(low, "gguf")
}

apply_gguf_tool_sampling :: proc(req: ^Chat_Request, provider_id, model, tools_json: string) {
	if req == nil || !gguf_sampling_applies(provider_id, model, tools_json) {
		return
	}
	cap_t := f64(constants.GGUF_TOOL_TEMP)
	if req.temperature_set {
		if req.temperature > cap_t {
			req.temperature = cap_t
		}
	} else {
		req.temperature = cap_t
		req.temperature_set = true
	}
	if !req.repetition_penalty_set {
		req.repetition_penalty = constants.GGUF_TOOL_REP_PENALTY
		req.repetition_penalty_set = true
	}
}

write_repeat_penalty_json :: proc(b: ^strings.Builder, p: ^Provider, req: Chat_Request) {
	if !req.repetition_penalty_set {
		return
	}
	local := p != nil && provider_is_local(p.id)
	gguf := strings.contains(strings.to_lower(req.model, context.temp_allocator), "gguf")
	if !local && !gguf {
		return
	}
	fmt.sbprintf(b, `,"repeat_penalty":%.4g`, req.repetition_penalty)
}
