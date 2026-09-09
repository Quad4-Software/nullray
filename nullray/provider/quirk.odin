// SPDX-License-Identifier: 0BSD
/*
Model output quirks applied once on final Chat_Response before speculate handoff.
*/

package provider

import "core:fmt"
import "core:os"
import "core:strings"
import "nullray:constants"

Quirk_Entry :: struct {
	id:   string,
	desc: string,
}

QUIRK_TOOL_XML_IN_REASONING :: "tool_xml_in_reasoning"
QUIRK_TOOL_JSON_IN_CONTENT :: "tool_json_in_content"
QUIRK_REASONING_ONLY_STALL :: "reasoning_only_stall"

BUILTIN_QUIRKS := []Quirk_Entry{
	{QUIRK_TOOL_XML_IN_REASONING, "extract Qwen-style tool XML from reasoning into tool_calls"},
	{QUIRK_TOOL_JSON_IN_CONTENT, "extract tool JSON from assistant content into tool_calls"},
	{QUIRK_REASONING_ONLY_STALL, "copy useful reasoning text when content and tool_calls are empty"},
}

Quirk_Mode :: enum {
	Default,
	Disabled,
	Explicit,
}

Quirk_Config :: struct {
	mode:    Quirk_Mode,
	enabled: map[string]bool,
}

@(private)
quirk_cfg: Quirk_Config
@(private)
quirk_cfg_loaded: bool

@(private)
quirk_env_disabled :: proc(v: string) -> bool {
	switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
	case "0", "false", "no", "off", "disable", "disabled":
		return true
	}
	return false
}

@(private)
quirk_model_is_qwen :: proc(model: string) -> bool {
	low := strings.to_lower(model, context.temp_allocator)
	return strings.contains(low, "qwen")
}

@(private)
quirk_load_config :: proc() {
	if quirk_cfg_loaded {
		return
	}
	quirk_cfg_loaded = true
	quirk_cfg.enabled = make(map[string]bool)
	v, ok := os.lookup_env(constants.ENV_QUIRKS, context.temp_allocator)
	if !ok || len(strings.trim_space(v)) == 0 {
		quirk_cfg.mode = .Default
		return
	}
	if quirk_env_disabled(v) {
		quirk_cfg.mode = .Disabled
		return
	}
	quirk_cfg.mode = .Explicit
	parts := strings.split(v, ",", context.temp_allocator)
	for part in parts {
		id := strings.trim_space(part)
		if len(id) == 0 {
			continue
		}
		quirk_cfg.enabled[strings.clone(id)] = true
	}
}

quirk_reset_config_for_test :: proc() {
	if quirk_cfg_loaded {
		for k in quirk_cfg.enabled {
			delete(k)
		}
		delete(quirk_cfg.enabled)
	}
	quirk_cfg = {}
	quirk_cfg_loaded = false
}

quirk_is_enabled :: proc(id: string, model: string) -> bool {
	quirk_load_config()
	switch quirk_cfg.mode {
	case .Disabled:
		return false
	case .Explicit:
		return quirk_cfg.enabled[id] == true
	case .Default:
		switch id {
		case QUIRK_TOOL_XML_IN_REASONING:
			return quirk_model_is_qwen(model)
		case QUIRK_TOOL_JSON_IN_CONTENT, QUIRK_REASONING_ONLY_STALL:
			return true
		}
	}
	return false
}

quirks_active_labels :: proc(model: string, allocator := context.allocator) -> string {
	quirk_load_config()
	b: strings.Builder
	strings.builder_init(&b, allocator)
	switch quirk_cfg.mode {
	case .Disabled:
		strings.write_string(&b, "quirks off (NULLRAY_QUIRKS=0)")
	case .Explicit:
		strings.write_string(&b, "quirks explicit: ")
		first := true
		for q in BUILTIN_QUIRKS {
			if quirk_cfg.enabled[q.id] == true {
				if !first {
					strings.write_string(&b, ", ")
				}
				strings.write_string(&b, q.id)
				first = false
			}
		}
		if first {
			strings.write_string(&b, "(none enabled)")
		}
	case .Default:
		strings.write_string(&b, "quirks default: ")
		first := true
		for q in BUILTIN_QUIRKS {
			if quirk_is_enabled(q.id, model) {
				if !first {
					strings.write_string(&b, ", ")
				}
				strings.write_string(&b, q.id)
				first = false
			}
		}
	}
	strings.write_string(&b, "\n")
	for q in BUILTIN_QUIRKS {
		on := quirk_is_enabled(q.id, model) ? "on" : "off"
		fmt.sbprintf(&b, "  %s [%s] - %s\n", q.id, on, q.desc)
	}
	return strings.to_string(b)
}

apply_quirks :: proc(res: ^Chat_Response, model: string, allocator := context.allocator) {
	if res == nil || !res.ok {
		return
	}
	if quirk_is_enabled(QUIRK_TOOL_XML_IN_REASONING, model) {
		quirk_apply_tool_xml_in_reasoning(res, allocator)
	}
	if quirk_is_enabled(QUIRK_TOOL_JSON_IN_CONTENT, model) {
		quirk_apply_tool_json_in_content(res, allocator)
	}
	if quirk_is_enabled(QUIRK_REASONING_ONLY_STALL, model) {
		quirk_apply_reasoning_only_stall(res, allocator)
	}
}
