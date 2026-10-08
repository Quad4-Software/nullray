// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Extra skill search roots from NULLRAY_SKILLS and --skills.
Users drop their own skill files into those dirs. There is no install command.
*/

package skills

import "core:fmt"
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

/*
Write a skill markdown file under the default user skills dir
(~/.config/nullray/skills/<id>.md). Caps body size. Safe overwrite.
Returns owned path and empty err on success.
*/
skills_save :: proc(
	id: string,
	name: string,
	description: string,
	body: string,
	paths: []string = nil,
	allocator := context.allocator,
) -> (path: string, err: string) {
	raw_id := strings.trim_space(id)
	if len(raw_id) == 0 {
		raw_id = strings.trim_space(name)
	}
	if len(raw_id) == 0 {
		return "", strings.clone("skill id required", allocator)
	}
	// Allow alnum _ - only.
	b_id: strings.Builder
	strings.builder_init(&b_id, context.temp_allocator)
	for r in raw_id {
		switch r {
		case 'a' ..= 'z', 'A' ..= 'Z', '0' ..= '9', '-', '_':
			strings.write_rune(&b_id, r)
		case ' ', '/':
			strings.write_byte(&b_id, '-')
		}
	}
	safe := strings.to_lower(strings.to_string(b_id), context.temp_allocator)
	if len(safe) == 0 {
		return "", strings.clone("skill id invalid", allocator)
	}
	if len(safe) > 64 {
		safe = safe[:64]
	}
	desc := strings.trim_space(description)
	if len(desc) == 0 {
		desc = strings.trim_space(name)
	}
	if len(desc) == 0 {
		desc = safe
	}
	if len(desc) > 400 {
		desc = desc[:400]
	}
	body_s := body
	if len(body_s) > MAX_SKILL_BYTES {
		return "", strings.clone("skill body too large", allocator)
	}
	nm := strings.trim_space(name)
	if len(nm) == 0 {
		nm = safe
	}
	dir := default_skills_dir(context.temp_allocator)
	if len(dir) == 0 {
		return "", strings.clone("skills dir unavailable", allocator)
	}
	_ = os.make_directory_all(dir)
	joined, jerr := filepath.join({dir, fmt.tprintf("%s.md", safe)}, context.temp_allocator)
	if jerr != nil {
		joined = fmt.tprintf("%s/%s.md", dir, safe)
	}
	fb: strings.Builder
	strings.builder_init(&fb, context.temp_allocator)
	strings.write_string(&fb, "---\n")
	fmt.sbprintf(&fb, "name: %s\n", nm)
	fmt.sbprintf(&fb, "description: %s\n", desc)
	if len(paths) > 0 {
		strings.write_string(&fb, "paths:\n")
		for p in paths {
			t := strings.trim_space(p)
			if len(t) == 0 {
				continue
			}
			fmt.sbprintf(&fb, "  - %s\n", t)
		}
	}
	strings.write_string(&fb, "---\n\n")
	strings.write_string(&fb, body_s)
	if !strings.has_suffix(body_s, "\n") {
		strings.write_byte(&fb, '\n')
	}
	data := strings.to_string(fb)
	if os.write_entire_file(joined, transmute([]u8)data) != nil {
		return "", strings.clone("failed to write skill file", allocator)
	}
	return strings.clone(joined, allocator), ""
}

skills_delete :: proc(id: string) -> bool {
	safe := strings.trim_space(id)
	if len(safe) == 0 {
		return false
	}
	dir := default_skills_dir(context.temp_allocator)
	path, _ := filepath.join({dir, fmt.tprintf("%s.md", safe)}, context.temp_allocator)
	if os.remove(path) == nil {
		return true
	}
	// nested SKILL.md form
	nested, _ := filepath.join({dir, safe, "SKILL.md"}, context.temp_allocator)
	return os.remove(nested) == nil
}
