/*
Session metadata JSON next to transcript files.
*/

package store

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"

Session_Meta :: struct {
	provider: string,
	model:    string,
	group:    string,
	mode:     string,
}

meta_path_for :: proc(session_jsonl_path: string, allocator := context.allocator) -> string {
	if strings.has_suffix(session_jsonl_path, ".jsonl") {
		base := session_jsonl_path[:len(session_jsonl_path) - 5]
		return fmt.aprintf("%s.meta.json", base, allocator = allocator)
	}
	return fmt.aprintf("%s.meta.json", session_jsonl_path, allocator = allocator)
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
	return meta, true
}

destroy_session_meta :: proc(meta: Session_Meta) {
	delete(meta.provider)
	delete(meta.model)
	delete(meta.group)
	delete(meta.mode)
}

