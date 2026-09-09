// SPDX-License-Identifier: 0BSD
/*
Session metadata JSON next to transcript files.
*/

package store

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"

Session_Meta :: struct {
	provider:              string,
	model:                 string,
	group:                 string,
	mode:                  string,
	turns:                 int,
	prompt_tokens:         int,
	completion_tokens:     int,
	total_tokens:          int,
	reasoning_tokens:      int,
	cost_usd:              f64,
	cost_known:            bool,
	peak_input_chars:      int,
	last_input_chars:      int,
	subagent_total_tokens: int,
}

meta_path_for :: proc(session_jsonl_path: string, allocator := context.allocator) -> string {
	base := session_file_stem(session_jsonl_path, context.temp_allocator)
	return fmt.aprintf("%s.meta.json", base, allocator = allocator)
}

save_session_meta :: proc(session_jsonl_path: string, meta: Session_Meta) -> bool {
	path := meta_path_for(session_jsonl_path, context.temp_allocator)
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	strings.write_string(&b, `{"provider":`)
	strings.write_string(&b, json_quote(meta.provider))
	strings.write_string(&b, `,"model":`)
	strings.write_string(&b, json_quote(meta.model))
	strings.write_string(&b, `,"group":`)
	strings.write_string(&b, json_quote(meta.group))
	strings.write_string(&b, `,"mode":`)
	strings.write_string(&b, json_quote(meta.mode))
	fmt.sbprintf(&b, `,"turns":%d`, meta.turns)
	fmt.sbprintf(&b, `,"prompt_tokens":%d`, meta.prompt_tokens)
	fmt.sbprintf(&b, `,"completion_tokens":%d`, meta.completion_tokens)
	fmt.sbprintf(&b, `,"total_tokens":%d`, meta.total_tokens)
	fmt.sbprintf(&b, `,"reasoning_tokens":%d`, meta.reasoning_tokens)
	fmt.sbprintf(&b, `,"cost_usd":%.6f`, meta.cost_usd)
	fmt.sbprintf(&b, `,"cost_known":%v`, meta.cost_known)
	fmt.sbprintf(&b, `,"peak_input_chars":%d`, meta.peak_input_chars)
	fmt.sbprintf(&b, `,"last_input_chars":%d`, meta.last_input_chars)
	fmt.sbprintf(&b, `,"subagent_total_tokens":%d`, meta.subagent_total_tokens)
	strings.write_string(&b, "}\n")
	return os.write_entire_file(path, transmute([]u8)strings.to_string(b)) == nil
}

load_session_meta :: proc(session_jsonl_path: string, allocator := context.allocator) -> (meta: Session_Meta, ok: bool) {
	path := meta_path_for(session_jsonl_path, context.temp_allocator)
	data, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil || len(data) == 0 {
		return {}, false
	}
	doc, perr := json.parse_string(string(data), .JSON, allocator = context.temp_allocator)
	if perr != .None {
		return {}, false
	}
	obj, ook := doc.(json.Object)
	if !ook {
		return {}, false
	}
	if v, vok := obj["provider"]; vok {
		if s, sok := v.(json.String); sok {
			meta.provider = strings.clone(string(s), allocator)
		}
	}
	if v, vok := obj["model"]; vok {
		if s, sok := v.(json.String); sok {
			meta.model = strings.clone(string(s), allocator)
		}
	}
	if v, vok := obj["group"]; vok {
		if s, sok := v.(json.String); sok {
			meta.group = strings.clone(string(s), allocator)
		}
	}
	if v, vok := obj["mode"]; vok {
		if s, sok := v.(json.String); sok {
			meta.mode = strings.clone(string(s), allocator)
		}
	}
	meta.turns = meta_json_int(obj, "turns")
	meta.prompt_tokens = meta_json_int(obj, "prompt_tokens")
	meta.completion_tokens = meta_json_int(obj, "completion_tokens")
	meta.total_tokens = meta_json_int(obj, "total_tokens")
	meta.reasoning_tokens = meta_json_int(obj, "reasoning_tokens")
	meta.peak_input_chars = meta_json_int(obj, "peak_input_chars")
	meta.last_input_chars = meta_json_int(obj, "last_input_chars")
	meta.subagent_total_tokens = meta_json_int(obj, "subagent_total_tokens")
	meta.cost_usd = meta_json_float(obj, "cost_usd")
	meta.cost_known = meta_json_bool(obj, "cost_known")
	return meta, true
}

destroy_session_meta :: proc(meta: Session_Meta) {
	delete(meta.provider)
	delete(meta.model)
	delete(meta.group)
	delete(meta.mode)
}

@(private)
meta_json_int :: proc(obj: json.Object, key: string) -> int {
	v, ok := obj[key]
	if !ok {
		return 0
	}
	#partial switch n in v {
	case json.Integer:
		return int(n)
	case json.Float:
		return int(n)
	}
	return 0
}

@(private)
meta_json_float :: proc(obj: json.Object, key: string) -> f64 {
	v, ok := obj[key]
	if !ok {
		return 0
	}
	#partial switch n in v {
	case json.Float:
		return f64(n)
	case json.Integer:
		return f64(n)
	}
	return 0
}

@(private)
meta_json_bool :: proc(obj: json.Object, key: string) -> bool {
	v, ok := obj[key]
	if !ok {
		return false
	}
	#partial switch b in v {
	case json.Boolean:
		return bool(b)
	}
	return false
}
