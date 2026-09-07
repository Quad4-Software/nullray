// SPDX-License-Identifier: 0BSD
/*
load_skill and list_skills tools for progressive skill disclosure.
*/

package tools

import "core:fmt"
import "core:strings"
import "nullray:skills"

tool_list_skills :: proc(args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	_ = args_json
	loaded, _ := skills.load_default(allocator)
	defer skills.skills_destroy(&loaded)
	if len(loaded) == 0 {
		return strings.clone("no skills found", allocator), ""
	}
	b: strings.Builder
	strings.builder_init(&b, allocator)
	for s, i in loaded {
		if i > 0 {
			strings.write_byte(&b, '\n')
		}
		strings.write_string(&b, s.id)
		strings.write_string(&b, ": ")
		desc := s.description
		if len(desc) == 0 {
			desc = s.name
		}
		strings.write_string(&b, desc)
	}
	return strings.to_string(b), ""
}

tool_load_skill :: proc(args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	id, perr := json_arg_string(args_json, "id", allocator)
	if perr != "" {
		return "", perr
	}
	defer delete(id)
	loaded, _ := skills.load_default(allocator)
	defer skills.skills_destroy(&loaded)
	sk, ok := skills.find_by_id(loaded[:], id)
	if !ok {
		return "", fmt.aprintf("unknown skill id: %s (use list_skills)", id, allocator = allocator)
	}
	return skills.format_skill_payload(sk, "load_skill", allocator), ""
}
