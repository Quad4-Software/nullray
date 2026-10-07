// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Constraint strength modes for tool-call decoding (see tool_constrain.odin
for the gate and body writer). Full GBNF/json-schema constraints push tool
call validity to 100% but tax reasoning on small local models, so the mode
decides how much of the schema the model must satisfy at decode time:

  strict -> full grammar/schema, argument values locked to enums and consts.
  shape  -> envelope, tool names, required keys and JSON types locked;
            argument values stay free (reason free, constrain the shape).
  late   -> phase 1 sends no constraint at all; only a malformed tool call
            resends with the strict constraint (constrained_retry flag).
            Prefix caching (llama.cpp cache_prompt, ollama keep_alive)
            makes the resend reuse the prompt KV, so it is cheap.

Resolution order in constrained_mode_effective: a shape rejection already
recorded on the provider drops to late, then NULLRAY_CONSTRAINED_MODE, then
the profile constrained_mode field, then the auto default. Auto default
picks strict only for models not known-weak (parameter size at or above
CONSTRAINED_STRONG_PARAMS_B from caps or the model id); every other local
model starts at shape.
*/

package provider

import "core:encoding/json"
import "core:os"
import "core:strconv"
import "core:strings"
import "nullray:constants"

Constrained_Mode :: enum {
	Unset,
	Strict,
	Shape,
	Late,
}

// Parameter count in billions at which a local model counts as strong
// enough to carry the full grammar without the reasoning tax.
CONSTRAINED_STRONG_PARAMS_B :: 32.0

// Name fragments that mark a small model when no numeric size is available.
@(private)
CONSTRAINED_WEAK_MODEL_KEYS :: []string{"mini", "nano", "tiny", "small", "micro"}

constrained_mode_parse :: proc(s: string) -> Constrained_Mode {
	switch strings.to_lower(strings.trim_space(s), context.temp_allocator) {
	case "strict", "full", "hard":
		return .Strict
	case "shape", "soft", "shallow":
		return .Shape
	case "late", "two-phase", "two_phase", "retry":
		return .Late
	}
	return .Unset
}

constrained_mode_name :: proc(m: Constrained_Mode) -> string {
	switch m {
	case .Strict:
		return "strict"
	case .Shape:
		return "shape"
	case .Late:
		return "late"
	case .Unset:
	}
	return ""
}

// Effective mode for this request: session latch, env, profile, then the
// capability auto default.
constrained_mode_effective :: proc(p: ^Provider, model: string) -> Constrained_Mode {
	if p == nil {
		return .Unset
	}
	// A shape field the server rejected once degrades to late for the
	// session. Checked first so an explicit shape setting cannot loop on
	// a server that refuses it.
	if p.constrained_late {
		return .Late
	}
	if v, ok := os.lookup_env(constants.ENV_CONSTRAINED_MODE, context.temp_allocator); ok {
		if m := constrained_mode_parse(v); m != .Unset {
			return m
		}
	}
	if prof, found := profile_for(model); found && prof.constrained_mode != .Unset {
		return prof.constrained_mode
	}
	if model_known_weak(p, model) {
		return .Shape
	}
	return .Strict
}

// Mode this request would send under, .Unset when no constraint field is
// written. Late phase 1 (constrained_retry unset) writes nothing.
constrained_field_mode :: proc(p: ^Provider, model: string, req: Chat_Request) -> Constrained_Mode {
	if p == nil || len(req.tools_json) == 0 {
		return .Unset
	}
	if !constrained_tools_enabled(p, model) {
		return .Unset
	}
	mode := constrained_mode_effective(p, model)
	if mode == .Late && !req.constrained_retry {
		return .Unset
	}
	return mode
}

// Late mode phase 2 gate: phase 1 ran unconstrained and produced malformed
// tool calls, so the caller should resend once with constrained_retry set.
// Returns false once the flag is already set so the resend never loops.
constrained_late_resend :: proc(p: ^Provider, model: string, req: Chat_Request, malformed: bool) -> bool {
	if p == nil || req.constrained_retry || !malformed {
		return false
	}
	if len(req.tools_json) == 0 || !constrained_tools_enabled(p, model) {
		return false
	}
	return constrained_mode_effective(p, model) == .Late
}

// True when any call carries arguments that do not parse as JSON. Empty
// args are fine, the request writer substitutes {} on replay.
tool_call_args_malformed :: proc(calls: []Tool_Call) -> bool {
	for tc in calls {
		if tool_args_unparseable(tc.arguments) {
			return true
		}
	}
	return false
}

@(private)
tool_args_unparseable :: proc(args: string) -> bool {
	t := strings.trim_space(args)
	if len(t) == 0 {
		return false
	}
	_, err := json.parse_string(t, .JSON, allocator = context.temp_allocator)
	return err != .None
}

// Small local models pay the reasoning tax under a full grammar. Probed
// parameter size wins, then a size token in the model id, then weak-name
// fragments. No size signal at all defaults to weak: shape costs nothing.
model_known_weak :: proc(p: ^Provider, model: string) -> bool {
	if p != nil && len(p.caps.parameter_size) > 0 {
		if b, ok := param_size_billions(p.caps.parameter_size); ok {
			return b < CONSTRAINED_STRONG_PARAMS_B
		}
	}
	if b, ok := model_size_billions(model); ok {
		return b < CONSTRAINED_STRONG_PARAMS_B
	}
	low := strings.to_lower(model, context.temp_allocator)
	for kw in CONSTRAINED_WEAK_MODEL_KEYS {
		if strings.contains(low, kw) {
			return true
		}
	}
	return true
}

// Parse "7.6B", "40B", "500M" style parameter counts into billions.
@(private)
param_size_billions :: proc(s: string) -> (f64, bool) {
	t := strings.trim_space(s)
	i := 0
	for i < len(t) && ((t[i] >= '0' && t[i] <= '9') || t[i] == '.') {
		i += 1
	}
	if i == 0 {
		return 0, false
	}
	n, ok := strconv.parse_f64(t[:i])
	if !ok {
		return 0, false
	}
	suffix := strings.to_lower(strings.trim_space(t[i:]), context.temp_allocator)
	switch suffix {
	case "", "b":
		return n, true
	case "m":
		return n / 1000, true
	case "k":
		return n / 1_000_000, true
	case "t":
		return n * 1000, true
	}
	return 0, false
}

// Extract the rightmost "<digits>b" size token from a model id:
// "qwen3:8b" -> 8, "llama3.1:70b" -> 70, "gemma-3-27b" -> 27.
@(private)
model_size_billions :: proc(model: string) -> (f64, bool) {
	m := strings.to_lower(model, context.temp_allocator)
	for i := len(m) - 1; i > 0; i -= 1 {
		if m[i] != 'b' {
			continue
		}
		j := i
		for j > 0 && ((m[j-1] >= '0' && m[j-1] <= '9') || m[j-1] == '.') {
			j -= 1
		}
		num := m[j:i]
		digits, dots := 0, 0
		for k in 0 ..< len(num) {
			if num[k] == '.' {
				dots += 1
			} else {
				digits += 1
			}
		}
		if digits == 0 || dots > 1 {
			continue
		}
		if n, ok := strconv.parse_f64(num); ok {
			return n, true
		}
	}
	return 0, false
}
