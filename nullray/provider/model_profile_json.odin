// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
model_profiles.json parse and serialize for Model_Profile. Unknown fields are
ignored, numbers accept JSON number or string forms, booleans accept bool,
"true"-style strings, or nonzero ints. Entries without a match glob are
skipped.
*/

package provider

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strconv"
import "core:strings"
import "nullray:constants"
import "nullray:sandbox"

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
	if v, ok := o["constrained_tools"]; ok {
		p.constrained_tools = profile_json_bool(v)
		p.constrained_tools_set = true
	}
	if v, ok := o["tool_names"]; ok {
		if obj, is_obj := v.(json.Object); is_obj {
			p.tool_names = make(map[string]string, allocator)
			for k, val in obj {
				if s, is_str := val.(json.String); is_str {
					key := strings.clone(k, allocator)
					p.tool_names[key] = strings.clone(string(s), allocator)
				}
			}
		}
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

// Serialize back to the model_profiles.json shape, used by tests and dumps.
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
		if p.constrained_tools_set {
			strings.write_string(&b, p.constrained_tools ? `,"constrained_tools":true` : `,"constrained_tools":false`)
		}
		if len(p.tool_names) > 0 {
			write_tool_names_json(&b, p.tool_names)
		}
		strings.write_byte(&b, '}')
	}
	strings.write_string(&b, `]}`)
	return strings.to_string(b)
}

// Emit a tool_names object with sorted keys so serialize output is stable.
@(private)
write_tool_names_json :: proc(b: ^strings.Builder, names: map[string]string) {
	keys := make([dynamic]string, 0, len(names), context.temp_allocator)
	for k in names {
		append(&keys, k)
	}
	slice.sort(keys[:])
	strings.write_string(b, `,"tool_names":{`)
	for k, i in keys {
		if i > 0 {
			strings.write_byte(b, ',')
		}
		write_json_string(b, k)
		strings.write_byte(b, ':')
		write_json_string(b, names[k])
	}
	strings.write_byte(b, '}')
}

/*
Write or update one profile's tool_names table in
<config dir>/model_profiles.json, preserving every other field and profile.
match is the profile glob (the probe writes the exact model id). Returns the
file path on success.
*/
profile_save_tool_names :: proc(match: string, tool_names: map[string]string, allocator := context.allocator) -> (path: string, err: string) {
	if len(strings.trim_space(match)) == 0 {
		return "", "empty match glob"
	}
	cfg_dir := sandbox.resolve_config_dir(context.temp_allocator)
	if len(cfg_dir) == 0 {
		return "", "cannot resolve config dir"
	}
	p, jerr := filepath.join({cfg_dir, constants.MODEL_PROFILES_FILE}, allocator)
	if jerr != nil {
		return "", "cannot build profile path"
	}
	root: json.Object
	if data, rerr := os.read_entire_file(p, context.temp_allocator); rerr == nil && len(data) > 0 {
		if doc, perr := json.parse_string(string(data), .JSON, allocator = context.temp_allocator); perr == .None {
			if obj, ok := doc.(json.Object); ok {
				root = obj
			}
		}
	}
	if root == nil {
		root = make(json.Object, context.temp_allocator)
	}
	profiles: json.Array
	if pv, ok := root["profiles"].(json.Array); ok {
		profiles = pv
	} else {
		profiles = make(json.Array, 0, 1, context.temp_allocator)
	}
	tn := make(json.Object, context.temp_allocator)
	for k, v in tool_names {
		tn[k] = json.String(strings.clone(v, context.temp_allocator))
	}
	found := false
	for item in profiles {
		io, is_obj := item.(json.Object)
		if !is_obj {
			continue
		}
		if m, is_str := io["match"].(json.String); is_str && string(m) == match {
			io["tool_names"] = tn
			found = true
		}
	}
	if !found {
		entry := make(json.Object, context.temp_allocator)
		entry["match"] = json.String(strings.clone(match, context.temp_allocator))
		entry["tool_names"] = tn
		append(&profiles, entry)
	}
	root["profiles"] = profiles
	out, merr := json.marshal(root, allocator = context.temp_allocator)
	if merr != nil {
		return "", "cannot encode model_profiles.json"
	}
	// make_directory_all errors on an already-existing dir, that is fine here.
	if !os.is_dir(cfg_dir) {
		if derr := os.make_directory_all(cfg_dir); derr != nil {
			return "", "cannot create config dir"
		}
	}
	if werr := os.write_entire_file(p, out); werr != nil {
		return "", "cannot write model_profiles.json"
	}
	return p, ""
}
