// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
LID harness helpers: metrics, tool envelopes, artifact offload, prepare ladder.
*/

package agent

import "core:os"
import "core:strconv"
import "core:strings"
import "nullray:constants"
import "nullray:provider"
import "nullray:tools"

Harness_Metrics :: struct {
	call_count:             int,
	total_prompt_chars:     int,
	peak_prompt_chars:      int,
	stubbed_bytes:          int,
	retained_tool_bytes:    int,
	artifacts_stored:       int,
	compact_events:         int,
	clear_events:           int,
	writeback_events:       int,
	midturn_prepare_events: int,
	tools_json_chars:       int,
	speculate_hit:          int,
	speculate_miss:         int,
	speculate_submit:       int,
	speculate_saved_ms:     int,
	diet_saved_chars:       int,
	corvus_saved_chars:     int,
	stash_saved_chars:      int,
}

Prepare_Stats :: struct {
	cleared:       int,
	compacted:     bool,
	writeback:     bool,
	stubbed_bytes: int,
}

Prepare_Context_Proc :: #type proc(
	msgs: ^[dynamic]provider.Message,
	p: ^provider.Provider,
	user: rawptr,
) -> Prepare_Stats

harness_metrics_enabled :: proc() -> bool {
	if v, ok := os.lookup_env(constants.ENV_HARNESS_METRICS, context.temp_allocator); ok {
		switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
		case "1", "true", "yes", "on":
			return true
		case "0", "false", "no", "off":
			return false
		}
	}
	if v, ok := os.lookup_env(constants.ENV_DEBUG, context.temp_allocator); ok {
		switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
		case "1", "true", "yes", "on":
			return true
		}
	}
	return false
}

lid_enabled :: proc() -> bool {
	if v, ok := os.lookup_env(constants.ENV_LID, context.temp_allocator); ok {
		switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
		case "0", "false", "no", "off", "disable":
			return false
		case "1", "true", "yes", "on":
			return true
		}
	}
	return true
}

// NULLRAY_PROMPT=full|lean|tiny|auto. auto is the default: Lean in print mode
// and Tiny when the active provider is local (small local models drown in a
// full tool catalog). Override explicitly when running a large local model.
prompt_tier_for :: proc(provider_id := "") -> tools.Prompt_Tier {
	return prompt_tier_for_model(provider_id, "")
}

// Same resolution as prompt_tier_for, plus the per-model profile table: when
// a matching model_profiles.json entry sets prompt_tier it wins over the env
// and provider heuristics. Model "" skips the profile lookup entirely.
prompt_tier_for_model :: proc(provider_id := "", model := "") -> tools.Prompt_Tier {
	if len(model) > 0 {
		if prof, ok := provider.profile_for(model); ok {
			switch prof.prompt_tier {
			case .Tiny:
				return .Tiny
			case .Lean:
				return .Lean
			case .Full:
				return .Full
			case .Unset:
			}
		}
	}
	return prompt_tier_for_heuristic(provider_id)
}

@(private)
prompt_tier_for_heuristic :: proc(provider_id := "") -> tools.Prompt_Tier {
	if v, ok := os.lookup_env(constants.ENV_PROMPT, context.temp_allocator); ok {
		switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
		case "tiny":
			return .Tiny
		case "lean":
			return .Lean
		case "full":
			return .Full
		}
	}
	if provider.provider_is_local(provider_id) {
		return .Tiny
	}
	if print_mode_active() {
		return .Lean
	}
	return .Full
}

prompt_tier :: proc() -> tools.Prompt_Tier {
	return prompt_tier_for("")
}

prompt_lean_enabled :: proc() -> bool {
	return prompt_tier() != .Full
}

print_mode_active :: proc() -> bool {
	if v, ok := os.lookup_env(constants.ENV_PRINT, context.temp_allocator); ok {
		switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
		case "1", "true", "yes", "on":
			return true
		}
	}
	return false
}

projection_user_turns :: proc() -> int {
	if v, ok := os.lookup_env(constants.ENV_PROJECTION_TURNS, context.temp_allocator); ok {
		n, n_ok := strconv.parse_int(v)
		if n_ok && n >= 1 {
			return n
		}
	}
	return constants.PROJECTION_USER_TURNS_DEFAULT
}

projection_tool_stubs :: proc() -> int {
	if v, ok := os.lookup_env(constants.ENV_PROJECTION_TOOL_STUBS, context.temp_allocator); ok {
		n, n_ok := strconv.parse_int(v)
		if n_ok && n >= 1 {
			return n
		}
	}
	return constants.PROJECTION_TOOL_STUBS_DEFAULT
}

compact_chars_budget :: proc() -> int {
	if v, ok := os.lookup_env(constants.ENV_COMPACT_CHARS, context.temp_allocator); ok {
		n, n_ok := strconv.parse_int(v)
		if n_ok && n > 4_000 {
			return n
		}
		if n_ok && n == 0 {
			return 0
		}
	}
	return constants.COMPACT_CHARS_DEFAULT
}

tool_clear_keep :: proc() -> int {
	if v, ok := os.lookup_env(constants.ENV_TOOL_CLEAR_KEEP, context.temp_allocator); ok {
		n, n_ok := strconv.parse_int(v)
		if n_ok && n >= 1 {
			return n
		}
	}
	return constants.TOOL_CLEAR_KEEP_DEFAULT
}

messages_content_chars :: proc(msgs: []provider.Message) -> int {
	total := 0
	for m in msgs {
		total += len(m.content) + len(m.reasoning) + len(m.name)
		for tc in m.tool_calls {
			total += len(tc.name) + len(tc.arguments) + len(tc.id)
		}
	}
	return total
}

messages_content_chars_excluding_system :: proc(msgs: []provider.Message) -> int {
	total := 0
	for m in msgs {
		if m.role == .System {
			continue
		}
		total += len(m.content) + len(m.reasoning) + len(m.name)
		for tc in m.tool_calls {
			total += len(tc.name) + len(tc.arguments) + len(tc.id)
		}
	}
	return total
}

is_cleared_tool_content :: proc(content: string) -> bool {
	return strings.has_prefix(content, constants.TOOL_CLEAR_STUB_PREFIX) ||
		strings.contains(content, "artifact=")
}
