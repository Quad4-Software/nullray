// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Local model capability data and pure parsers.

Local_Caps records what a local server reports about a model: trained context
window, Modelfile num_ctx, live window, and capability flags (tools, vision,
thinking). The parse procs take fixture strings and do no IO so they are
unit-testable, the network side lives in ollama_probe.odin.
*/

package provider

import "core:encoding/json"
import "core:strconv"
import "core:strings"

// Probed facts about a local model or server. String fields are owned by the
// Provider and freed via local_caps_destroy in provider_destroy.
Local_Caps :: struct {
	probed:            bool,
	probed_model:      string, // model the caps describe
	context_length:    int,    // model_info *context_length (ollama) or n_ctx (llama.cpp)
	modelfile_num_ctx: int,    // Modelfile PARAMETER num_ctx (ollama)
	loaded_ctx:        int,    // /api/ps live window (ollama)
	parameter_size:    string, // details.parameter_size (ollama)
	total_slots:       int,    // llama.cpp /props
	tools_known:       bool,   // server reported capability data
	supports_tools:    bool,
	supports_vision:   bool,
	supports_thinking: bool,
}

local_caps_destroy :: proc(caps: ^Local_Caps) {
	if caps == nil {
		return
	}
	delete(caps.probed_model)
	delete(caps.parameter_size)
	caps^ = {}
}

@(private)
json_int_value :: proc(v: json.Value) -> int {
	#partial switch n in v {
	case json.Integer:
		return int(n)
	case json.Float:
		return int(n)
	}
	return 0
}

@(private)
json_bool_value :: proc(v: json.Value) -> (bool, bool) {
	if b, ok := v.(json.Boolean); ok {
		return bool(b), true
	}
	return false, false
}

// The parameters blob is rendered Modelfile PARAMETER lines, one per line,
// later entries override earlier ones.
parse_modelfile_num_ctx :: proc(parameters: string) -> int {
	n := 0
	rest := parameters
	for len(rest) > 0 {
		line := rest
		if idx := strings.index_byte(rest, '\n'); idx >= 0 {
			line = rest[:idx]
			rest = rest[idx + 1:]
		} else {
			rest = ""
		}
		fields := strings.fields(line, context.temp_allocator)
		if len(fields) < 2 || fields[0] != "num_ctx" {
			continue
		}
		if v, ok := strconv.parse_int(fields[1]); ok && v > 0 {
			n = v
		}
	}
	return n
}

// POST /api/show body. capabilities lists what the model can do (tools,
// thinking, vision, insert, completion), model_info carries per-architecture
// keys where the one ending in context_length is the trained window.
parse_ollama_show_body :: proc(body: string, allocator := context.allocator) -> Local_Caps {
	caps: Local_Caps
	doc, perr := json.parse_string(body, .JSON, allocator = context.temp_allocator)
	if perr != .None {
		return caps
	}
	obj, ok := doc.(json.Object)
	if !ok {
		return caps
	}
	if v, has := obj["capabilities"]; has {
		if arr, aok := v.(json.Array); aok {
			caps.tools_known = true
			for item in arr {
				s, sok := item.(json.String)
				if !sok {
					continue
				}
				switch string(s) {
				case "tools":
					caps.supports_tools = true
				case "vision":
					caps.supports_vision = true
				case "thinking":
					caps.supports_thinking = true
				}
			}
		}
	}
	if v, has := obj["model_info"]; has {
		if mi, mok := v.(json.Object); mok {
			for k, mv in mi {
				if !strings.has_suffix(k, "context_length") {
					continue
				}
				if n := json_int_value(mv); n > caps.context_length {
					caps.context_length = n
				}
			}
		}
	}
	if v, has := obj["parameters"]; has {
		if s, sok := v.(json.String); sok {
			caps.modelfile_num_ctx = parse_modelfile_num_ctx(string(s))
		}
	}
	if v, has := obj["details"]; has {
		if det, dok := v.(json.Object); dok {
			if psv, pok := det["parameter_size"]; pok {
				if s, sok := psv.(json.String); sok {
					caps.parameter_size = strings.clone(string(s), allocator)
				}
			}
		}
	}
	return caps
}

// GET /api/ps body. Returns the live window of the loaded model, or 0 when it
// is absent or not loaded. context_length appears on newer Ollama builds.
parse_ollama_ps_context :: proc(body, model: string) -> int {
	doc, perr := json.parse_string(body, .JSON, allocator = context.temp_allocator)
	if perr != .None {
		return 0
	}
	obj, ok := doc.(json.Object)
	if !ok {
		return 0
	}
	mv, has := obj["models"]
	arr, aok := mv.(json.Array)
	if !has || !aok {
		return 0
	}
	for item in arr {
		mobj, mok := item.(json.Object)
		if !mok {
			continue
		}
		if len(model) > 0 {
			name := ""
			if nv, nok := mobj["name"]; nok {
				if s, sok := nv.(json.String); sok {
					name = string(s)
				}
			}
			if len(name) == 0 {
				if nv, nok := mobj["model"]; nok {
					if s, sok := nv.(json.String); sok {
						name = string(s)
					}
				}
			}
			if name != model {
				continue
			}
		}
		return json_int_field(mobj, "context_length")
	}
	return 0
}

// GET /props body (llama-server). chat_template_tool_use and
// chat_template_caps.supports_tool_calls both describe tool support across
// server versions, n_ctx lives under default_generation_settings.
parse_llamacpp_props_body :: proc(body: string, allocator := context.allocator) -> Local_Caps {
	_ = allocator
	caps: Local_Caps
	doc, perr := json.parse_string(body, .JSON, allocator = context.temp_allocator)
	if perr != .None {
		return caps
	}
	obj, ok := doc.(json.Object)
	if !ok {
		return caps
	}
	caps.total_slots = json_int_field(obj, "total_slots")
	if v, has := obj["chat_template_tool_use"]; has {
		if b, bok := json_bool_value(v); bok {
			caps.tools_known = true
			caps.supports_tools = b
		}
	}
	if v, has := obj["chat_template_caps"]; has {
		if tc, tok := v.(json.Object); tok {
			if sv, sok := tc["supports_tool_calls"]; sok {
				if b, bok := json_bool_value(sv); bok {
					caps.tools_known = true
					caps.supports_tools = caps.supports_tools || b
				}
			}
		}
	}
	if v, has := obj["default_generation_settings"]; has {
		if gs, gok := v.(json.Object); gok {
			caps.context_length = json_int_field(gs, "n_ctx")
		}
	}
	if caps.context_length <= 0 {
		caps.context_length = json_int_field(obj, "n_ctx")
	}
	return caps
}

/*
Advisory flag for /providers and tool gating: false only when the server
reported capability data and tools were not in it. Unknown means assume yes
so older servers are not penalized for missing fields.
*/
provider_supports_tools :: proc(p: ^Provider) -> bool {
	if p == nil {
		return true
	}
	if p.caps.tools_known {
		return p.caps.supports_tools
	}
	return true
}
