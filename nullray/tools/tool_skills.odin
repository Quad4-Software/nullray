// SPDX-License-Identifier: 0BSD
/*
load_skill and list_skills tools for progressive skill disclosure.
*/

package tools

import "core:fmt"
import "nullray:skills"

tool_list_skills :: proc(args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	_ = args_json
	loaded, _ := skills.load_default(allocator)
	defer skills.skills_destroy(&loaded)
	return skills.format_list_text(loaded[:], allocator), ""
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
