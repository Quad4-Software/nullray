// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
model_profiles.json parse and serialize for Model_Profile. Unknown fields are
ignored; numbers accept JSON number or string forms; booleans accept bool,
"true"-style strings, or nonzero ints. Entries without a match glob are
skipped.
*/

package provider

import "core:encoding/json"
import "core:fmt"
import "core:strconv"
import "core:strings"

// Parse one model_profiles.json body. Caller owns the slice and each match
// string under the passed allocator.
profile_parse :: proc(text: string, allocator := context.allocator) -> []Model_Profile {
	doc, perr := json.parse_string(text, .JSON, allocator = context.temp_allocator)
	if perr != .None {
		return nil
	}
	obj, obj_ok := doc.(json.Object)
	if !obj_ok {
		return nil
	}
	pv, found := obj["profiles"]
	if !found {
		return nil
	}
	arr, arr_ok := pv.(json.Array)
	if !arr_ok {
		return nil
	}
	out := make([dynamic]Model_Profile, allocator)
	for item in arr {
		io, io_ok := item.(json.Object)
		if !io_ok {
			continue
		}
		p := profile_from_object(io, allocator)
		if len(p.match) == 0 {
			continue
		}
		append(&out, p)
	}
	return out[:]
}

@(private)
profile_from_object :: proc(o: json.Object, allocator := context.allocator) -> Model_Profile {
	p: Model_Profile
	if v, ok := o["match"]; ok {
		if s, is_str := v.(json.String); is_str {
			p.match = strings.clone(string(s), allocator)
		}
	}
	p.ctx = profile_json_int(o, "ctx")
	p.num_ctx = profile_json_int(o, "num_ctx")
	if v, ok := o["temperature"]; ok {
		if f, is_num := profile_json_f64(v); is_num {
			p.temperature = f
			p.temperature_set = true
		}
	}
	if v, ok := o["top_p"]; ok {
		if f, is_num := profile_json_f64(v); is_num {
			p.top_p = f
			p.top_p_set = true
		}
	}
	if v, ok := o["reasoning"]; ok {
		if s, is_str := v.(json.String); is_str {
			p.reasoning = profile_reasoning_from_string(string(s))
		}
	}
	if v, ok := o["one_tool_per_turn"]; ok {
		p.one_tool_per_turn = profile_json_bool(v)
	}
	if v, ok := o["prompt_tier"]; ok {
		if s, is_str := v.(json.String); is_str {
			p.prompt_tier = profile_tier_from_string(string(s))
		}
	}
	if v, ok := o["parallel_tool_calls"]; ok {
		p.parallel_tool_calls = profile_json_bool(v)
		p.parallel_tool_calls_set = true
	}
	return p
}

@(private)
profile_reasoning_from_string :: proc(s: string) -> Profile_Reasoning {
	switch strings.to_lower(strings.trim_space(s), context.temp_allocator) {
	case "off", "none", "disabled", "false":
		return .Off
	case "on", "enabled", "true", "low", "medium", "high", "max":
		return .On
	}
	return .Unset
}

@(private)
profile_tier_from_string :: proc(s: string) -> Profile_Prompt_Tier {
	switch strings.to_lower(strings.trim_space(s), context.temp_allocator) {
	case "tiny":
		return .Tiny
	case "lean":
		return .Lean
	case "full":
		return .Full
	}
	return .Unset
}

@(private)
profile_tier_name :: proc(tier: Profile_Prompt_Tier) -> string {
	switch tier {
	case .Tiny:
		return "tiny"
	case .Lean:
		return "lean"
	case .Full:
		return "full"
	case .Unset:
	}
	return ""
}

@(private)
profile_json_int :: proc(o: json.Object, key: string) -> int {
	v, ok := o[key]
	if !ok {
		return 0
	}
	#partial switch val in v {
	case json.Integer:
		return int(val)
	case json.Float:
		return int(val)
	case json.String:
		if n, nok := strconv.parse_int(strings.trim_space(string(val))); nok {
			return n
		}
	}
	return 0
}

@(private)
profile_json_f64 :: proc(v: json.Value) -> (f64, bool) {
	#partial switch val in v {
	case json.Integer:
		return f64(val), true
	case json.Float:
		return f64(val), true
	case json.String:
		if f, ok := strconv.parse_f64(strings.trim_space(string(val))); ok {
			return f, true
		}
	}
	return 0, false
}

@(private)
profile_json_bool :: proc(v: json.Value) -> bool {
	#partial switch val in v {
	case json.Boolean:
		return bool(val)
	case json.String:
		s := strings.to_lower(strings.trim_space(string(val)), context.temp_allocator)
		return s == "1" || s == "true" || s == "yes" || s == "on"
	case json.Integer:
		return val != 0
	}
	return false
}

// Serialize back to the model_profiles.json shape; used by tests and dumps.
profile_serialize :: proc(profiles: []Model_Profile, allocator := context.allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	strings.write_string(&b, `{"profiles":[`)
	for p, i in profiles {
		if i > 0 {
			strings.write_byte(&b, ',')
		}
		strings.write_string(&b, `{"match":`)
		write_json_string(&b, p.match)
		if p.ctx > 0 {
			fmt.sbprintf(&b, `,"ctx":%d`, p.ctx)
		}
		if p.num_ctx > 0 {
			fmt.sbprintf(&b, `,"num_ctx":%d`, p.num_ctx)
		}
		if p.temperature_set {
			fmt.sbprintf(&b, `,"temperature":%.4g`, p.temperature)
		}
		if p.top_p_set {
			fmt.sbprintf(&b, `,"top_p":%.4g`, p.top_p)
		}
		if p.reasoning == .Off {
			strings.write_string(&b, `,"reasoning":"off"`)
		} else if p.reasoning == .On {
			strings.write_string(&b, `,"reasoning":"on"`)
		}
		if p.one_tool_per_turn {
			strings.write_string(&b, `,"one_tool_per_turn":true`)
		}
		if p.prompt_tier != .Unset {
			fmt.sbprintf(&b, `,"prompt_tier":"%s"`, profile_tier_name(p.prompt_tier))
		}
		if p.parallel_tool_calls_set {
			strings.write_string(&b, p.parallel_tool_calls ? `,"parallel_tool_calls":true` : `,"parallel_tool_calls":false`)
		}
		strings.write_byte(&b, '}')
	}
	strings.write_string(&b, `]}`)
	return strings.to_string(b)
}
