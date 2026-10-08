// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
list_skills, load_skill, skill_write for progressive skill disclosure and
durable agent-authored skills under the user skills dir.
*/

package tools

import "core:fmt"
import "core:strings"
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

/*
Persist a compact skill for later sessions. Keep body short (token efficient).
Writes ~/.config/nullray/skills/<id>.md
*/
tool_skill_write :: proc(args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	id, _ := json_arg_string_optional(args_json, "id", "", allocator)
	defer delete(id)
	name, _ := json_arg_string_optional(args_json, "name", "", allocator)
	defer delete(name)
	desc, _ := json_arg_string_optional(args_json, "description", "", allocator)
	defer delete(desc)
	body, berr := json_arg_string(args_json, "body", allocator)
	if berr != "" {
		// also accept "content"
		body2, berr2 := json_arg_string(args_json, "content", allocator)
		if berr2 != "" {
			return "", strings.clone("body required (short skill text)", allocator)
		}
		body = body2
	}
	defer delete(body)
	if len(strings.trim_space(body)) == 0 {
		return "", strings.clone("empty skill body", allocator)
	}
	// Optional paths array as comma string for simplicity
	paths_raw, _ := json_arg_string_optional(args_json, "paths", "", context.temp_allocator)
	path_list: [dynamic]string
	path_list.allocator = context.temp_allocator
	if len(paths_raw) > 0 {
		for p in strings.split(paths_raw, ",", context.temp_allocator) {
			t := strings.trim_space(p)
			if len(t) > 0 {
				append(&path_list, t)
			}
		}
	}
	path, serr := skills.skills_save(id, name, desc, body, path_list[:], allocator)
	if serr != "" {
		return "", serr
	}
	out := fmt.aprintf("skill saved path=%s (load with load_skill id, keep prompts short)", path, allocator = allocator)
	delete(path)
	return out, ""
}
