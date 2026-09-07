// SPDX-License-Identifier: 0BSD
/*
Skill markdown files loaded from config, workspace, and ~/.agents.
*/

package skills

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "nullray:constants"
import "nullray:sandbox"

Skill :: struct {
	id:     string,
	name:   string,
	body:   string,
	source: string,
}

MAX_SKILLS :: 48
MAX_SKILL_BYTES :: 24_000

load_dir :: proc(path: string, allocator := context.allocator) -> (skills: [dynamic]Skill, err: string) {
	skills = make([dynamic]Skill, allocator)
	entries, rerr := os.read_all_directory_by_path(path, allocator)
	if rerr != nil {
		return skills, fmt.aprintf("read skills dir failed: %v", rerr, allocator = allocator)
	}
	defer os.file_info_slice_delete(entries, allocator)
	for e in entries {
		if e.type == .Directory {
			continue
		}
		if !strings.has_suffix(e.name, ".md") {
			continue
		}
		fpath, ferr := filepath.join({path, e.name}, allocator)
		if ferr != nil {
			continue
		}
		sk, ok := load_skill_file(fpath, e.name[:len(e.name) - 3], path, allocator)
		delete(fpath)
		if ok {
			append(&skills, sk)
		}
	}
	return skills, ""
}

// Load SKILL.md from immediate child dirs (Agent Skills layout: name/SKILL.md).
load_nested_skill_md :: proc(root: string, allocator := context.allocator) -> [dynamic]Skill {
	out := make([dynamic]Skill, allocator)
	entries, rerr := os.read_all_directory_by_path(root, context.temp_allocator)
	if rerr != nil {
		return out
	}
	defer os.file_info_slice_delete(entries, context.temp_allocator)
	for e in entries {
		if e.type != .Directory {
			continue
		}
		if strings.has_prefix(e.name, ".") {
			continue
		}
		skill_path, jerr := filepath.join({root, e.name, "SKILL.md"}, context.temp_allocator)
		if jerr != nil {
			continue
		}
		sk, ok := load_skill_file(skill_path, e.name, root, allocator)
		if ok {
			append(&out, sk)
		}
	}
	return out
}

load_skill_file :: proc(path, id, source: string, allocator := context.allocator) -> (Skill, bool) {
	data, derr := os.read_entire_file(path, allocator)
	if derr != nil || len(data) == 0 {
		return {}, false
	}
	if len(data) > MAX_SKILL_BYTES {
		trimmed := strings.clone(string(data[:MAX_SKILL_BYTES]), allocator)
		delete(data)
		data = transmute([]u8)trimmed
	}
	tmp, _ := strings.replace_all(id, "-", " ", context.temp_allocator)
	tmp, _ = strings.replace_all(tmp, "_", " ", context.temp_allocator)
	return Skill{
		id = strings.clone(id, allocator),
		name = strings.clone(tmp, allocator),
		body = string(data),
		source = strings.clone(source, allocator),
	}, true
}

skill_roots :: proc(allocator := context.temp_allocator) -> []string {
	roots := make([dynamic]string, 0, 8, allocator)
	seen := make(map[string]bool, allocator)
	bare := bare_skills_only()

	add :: proc(roots: ^[dynamic]string, seen: ^map[string]bool, parts: []string) {
		path, jerr := filepath.join(parts, context.temp_allocator)
		if jerr != nil || len(path) == 0 {
			return
		}
		clean, _ := filepath.clean(path, context.temp_allocator)
		if seen[clean] {
			return
		}
		info, err := os.stat(clean, context.temp_allocator)
		if err != nil || info.type != .Directory {
			return
		}
		seen[clean] = true
		append(roots, strings.clone(clean, roots.allocator))
	}

	st := sandbox.state()
	if st != nil && len(st.workspace) > 0 {
		add(&roots, &seen, {st.workspace, "skills"})
		add(&roots, &seen, {st.workspace, ".agents", "skills"})
		add(&roots, &seen, {st.workspace, ".agents"})
	}
	if cwd, err := os.get_working_directory(context.temp_allocator); err == nil {
		add(&roots, &seen, {cwd, "skills"})
		add(&roots, &seen, {cwd, ".agents", "skills"})
		add(&roots, &seen, {cwd, ".agents"})
	}

	if !bare {
		cfg := sandbox.resolve_config_dir(context.temp_allocator)
		add(&roots, &seen, {cfg, constants.SKILLS_DIR})

		if home, ok := os.lookup_env("HOME", context.temp_allocator); ok && len(home) > 0 {
			add(&roots, &seen, {home, ".agents", "skills"})
			add(&roots, &seen, {home, ".agents"})
			add(&roots, &seen, {home, ".config", "nullray", "skills"})
		}
	}

	return roots[:]
}

@(private)
bare_skills_only :: proc() -> bool {
	if v, ok := os.lookup_env(constants.ENV_BARE, context.temp_allocator); ok {
		switch strings.to_lower(v, context.temp_allocator) {
		case "1", "true", "yes", "on":
			return true
		}
	}
	return false
}

load_default :: proc(allocator := context.allocator) -> (skills: [dynamic]Skill, err: string) {
	skills = make([dynamic]Skill, allocator)
	ids := make(map[string]bool, context.temp_allocator)
	roots := skill_roots(context.temp_allocator)

	for root in roots {
		// Flat *.md
		flat, _ := load_dir(root, allocator)
		for s in flat {
			if ids[s.id] || len(skills) >= MAX_SKILLS {
				delete(s.id)
				delete(s.name)
				delete(s.body)
				delete(s.source)
				continue
			}
			ids[s.id] = true
			append(&skills, s)
		}
		delete(flat)

		if len(skills) >= MAX_SKILLS {
			break
		}

		// Nested name/SKILL.md
		nested := load_nested_skill_md(root, allocator)
		for s in nested {
			if ids[s.id] || len(skills) >= MAX_SKILLS {
				delete(s.id)
				delete(s.name)
				delete(s.body)
				delete(s.source)
				continue
			}
			ids[s.id] = true
			append(&skills, s)
		}
		delete(nested)

		if len(skills) >= MAX_SKILLS {
			break
		}
	}
	return skills, ""
}

default_skills_dir :: proc(allocator := context.allocator) -> string {
	st := sandbox.state()
	if st != nil && st.applied && len(st.config_dir) > 0 {
		joined, jerr := filepath.join({st.config_dir, constants.SKILLS_DIR}, allocator)
		if jerr == nil {
			return joined
		}
	}
	base := sandbox.resolve_config_dir(allocator)
	defer delete(base)
	joined, jerr := filepath.join({base, constants.SKILLS_DIR}, allocator)
	if jerr != nil {
		return strings.clone("skills", allocator)
	}
	return joined
}

render_system_prompt :: proc(skills: []Skill, allocator := context.allocator) -> string {
	if len(skills) == 0 {
		return ""
	}
	b: strings.Builder
	strings.builder_init(&b, allocator)
	strings.write_string(&b, fmt.tprintf("Loaded %d skills (auto-detected).\n\n", len(skills)))
	for s, i in skills {
		if i > 0 {
			strings.write_string(&b, "\n\n")
		}
		strings.write_string(&b, fmt.tprintf("# Skill: %s\n\n", s.name))
		strings.write_string(&b, s.body)
	}
	return strings.to_string(b)
}

skills_destroy :: proc(skills: ^[dynamic]Skill) {
	for s in skills {
		delete(s.id)
		delete(s.name)
		delete(s.body)
		delete(s.source)
	}
	delete(skills^)
	skills^ = {}
}
