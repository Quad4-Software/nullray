// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Extra skill search roots from NULLRAY_SKILLS and --skills.
Users drop their own skill files into those dirs. There is no install command.
*/

package skills

import "core:os"
import "core:path/filepath"
import "core:strings"
import "nullray:constants"

/*
Split comma and OS path-list separators into trimmed paths.
Caller owns the returned slice strings when allocator is not temp.
*/
split_skills_paths :: proc(raw: string, allocator := context.allocator) -> []string {
	out := make([dynamic]string, 0, 4, allocator)
	if len(strings.trim_space(raw)) == 0 {
		return out[:]
	}
	start := 0
	for i := 0; i <= len(raw); i += 1 {
		at_end := i == len(raw)
		sep := false
		if !at_end {
			c := raw[i]
			if c == ',' || c == u8(filepath.LIST_SEPARATOR) {
				sep = true
			}
		} else {
			sep = true
		}
		if !sep {
			continue
		}
		part := strings.trim_space(raw[start:i])
		if len(part) > 0 {
			append(&out, strings.clone(part, allocator))
		}
		start = i + 1
	}
	return out[:]
}

skills_paths_from_env :: proc(allocator := context.allocator) -> []string {
	raw, ok := os.lookup_env(constants.ENV_SKILLS, context.temp_allocator)
	if !ok || len(strings.trim_space(raw)) == 0 {
		return {}
	}
	return split_skills_paths(raw, allocator)
}

resolve_skill_src :: proc(path: string, allocator := context.allocator) -> string {
	clean, cerr := filepath.clean(path, context.temp_allocator)
	if cerr != nil {
		clean = path
	}
	if filepath.is_abs(clean) {
		return strings.clone(clean, allocator)
	}
	cwd, err := os.get_working_directory(context.temp_allocator)
	if err != nil {
		return strings.clone(clean, allocator)
	}
	joined, jerr := filepath.join({cwd, clean}, allocator)
	if jerr != nil {
		return strings.clone(clean, allocator)
	}
	return joined
}

destroy_path_list :: proc(paths: []string, allocator := context.allocator) {
	for p in paths {
		delete(p, allocator)
	}
	delete(paths, allocator)
}
