// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
GGUF and local-server sampling for tool-call turns.

Local GGUF backends (llama.cpp, Ollama, LM Studio, or a model id that
contains gguf) lose tool-call format accuracy above about 0.3 temperature.
On turns that ship a tools JSON we clamp temperature to 0.2 and pin
repeat_penalty to 1.0 (identity, no extra penalty). NULLRAY_GGUF_SAMPLE=0
disables the clamp.

The cap is family- and quant-aware (quant-toolcall-bench, gguf-bench):
llama-family models lose tool-call schema validity sharply at Q4 and below
while qwen-family barely moves, so llama at low quant clamps to
GGUF_TOOL_TEMP_LLAMA_LOW and every other family/tier combo keeps the
default. Family and tier come from the model profile when set, else they
are sniffed from the model id or GGUF filename.
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

// Rank bounds for quant_tier_of_rank: a rank at or below QUANT_RANK_LOW_MAX
// is the lossy tier where llama-family degrades, QUANT_RANK_MID_MAX ends mid.
QUANT_RANK_LOW_MAX :: 4
QUANT_RANK_MID_MAX :: 6
// Stricter tool-turn cap for llama-family models at low quant.
GGUF_TOOL_TEMP_LLAMA_LOW :: 0.1

/*
quant_rank maps the quant tag inside a model id or GGUF filename to an
integer precision rank: q4_k_m -> 4, q8_0 -> 8, iq3_xs -> 3, f16/bf16 -> 16,
f32 -> 32. Returns -1 when no tag is found. The tag is normally the last
token, so the scan runs right to left looking for a q<digit> pair where the
q starts a token (a preceding letter rejects it, except i for imatrix iq
tags, so seq2seq does not false-positive).
*/
quant_rank :: proc(s: string) -> int {
	low := strings.to_lower(s, context.temp_allocator)
	for i := len(low) - 2; i >= 0; i -= 1 {
		if low[i] != 'q' || low[i + 1] < '0' || low[i + 1] > '9' {
			continue
		}
		if i == 0 || low[i - 1] < 'a' || low[i - 1] > 'z' || low[i - 1] == 'i' {
			return int(low[i + 1] - '0')
		}
	}
	if strings.contains(low, "f32") {
		return 32
	}
	if strings.contains(low, "f16") {
		return 16
	}
	return -1
}

quant_tier_of_rank :: proc(rank: int) -> Quant_Tier {
	if rank < 0 {
		return .Unset
	}
	if rank <= QUANT_RANK_LOW_MAX {
		return .Low
	}
	if rank <= QUANT_RANK_MID_MAX {
		return .Mid
	}
	return .High
}

quant_tier_detect :: proc(model: string) -> Quant_Tier {
	return quant_tier_of_rank(quant_rank(model))
}

/*
quant_family_detect sniffs the model family from an id or filename:
llama-* or *llama* maps to .Llama, *qwen* to .Qwen, anything else .Unset.
"ollama" embeds "llama", so a llama hit preceded by o is treated as the
provider name and the scan keeps looking for a real family token.
*/
quant_family_detect :: proc(model: string) -> Quant_Family {
	low := strings.to_lower(model, context.temp_allocator)
	at := 0
	for at < len(low) {
		i := strings.index(low[at:], "llama")
		if i < 0 {
			break
		}
		pos := at + i
		if pos == 0 || low[pos - 1] != 'o' {
			return .Llama
		}
		at = pos + 1
	}
	if strings.contains(low, "qwen") {
		return .Qwen
	}
	return .Unset
}

quant_family_from_string :: proc(s: string) -> Quant_Family {
	switch strings.to_lower(strings.trim_space(s), context.temp_allocator) {
	case "llama":
		return .Llama
	case "qwen":
		return .Qwen
	}
	return .Unset
}

// Accepts tier names (low|mid|high) or a raw quant tag like q4_k_m.
quant_tier_from_string :: proc(s: string) -> Quant_Tier {
	low := strings.to_lower(strings.trim_space(s), context.temp_allocator)
	switch low {
	case "low":
		return .Low
	case "mid":
		return .Mid
	case "high":
		return .High
	}
	return quant_tier_of_rank(quant_rank(low))
}

quant_family_name :: proc(f: Quant_Family) -> string {
	switch f {
	case .Llama:
		return "llama"
	case .Qwen:
		return "qwen"
	case .Unset:
	}
	return ""
}

quant_tier_name :: proc(t: Quant_Tier) -> string {
	switch t {
	case .Low:
		return "low"
	case .Mid:
		return "mid"
	case .High:
		return "high"
	case .Unset:
	}
	return ""
}

/*
Pure clamp matrix: llama-family at low quant gets GGUF_TOOL_TEMP_LLAMA_LOW,
every other family/tier combo keeps constants.GGUF_TOOL_TEMP. MoE and other
families tolerate aggressive quant better, so only the measured llama+Q4
regression earns the stricter cap.
*/
gguf_tool_temp_cap_for :: proc(family: Quant_Family, tier: Quant_Tier) -> f64 {
	if family == .Llama && tier == .Low {
		return GGUF_TOOL_TEMP_LLAMA_LOW
	}
	return f64(constants.GGUF_TOOL_TEMP)
}

/*
Resolve effective family and tier: profile values win when set, each unset
value falls back to sniffing the model id or GGUF filename. Pure so the
clamp matrix stays testable without touching the profile table.
*/
quant_resolve :: proc(prof_family: Quant_Family, prof_tier: Quant_Tier, model: string) -> (Quant_Family, Quant_Tier) {
	family := prof_family
	tier := prof_tier
	if family == .Unset {
		family = quant_family_detect(model)
	}
	if tier == .Unset {
		tier = quant_tier_detect(model)
	}
	return family, tier
}

// Resolve the tool-turn temperature cap for a model id via quant_resolve.
gguf_tool_temp_cap :: proc(model: string) -> f64 {
	family := Quant_Family.Unset
	tier := Quant_Tier.Unset
	if prof, ok := profile_for(model); ok {
		family = prof.quant_family
		tier = prof.quant_tier
	}
	return gguf_tool_temp_cap_for(quant_resolve(family, tier, model))
}

apply_gguf_tool_sampling :: proc(req: ^Chat_Request, provider_id, model, tools_json: string) {
	if req == nil || !gguf_sampling_applies(provider_id, model, tools_json) {
		return
	}
	cap_t := gguf_tool_temp_cap(model)
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
