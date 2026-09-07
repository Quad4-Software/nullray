// SPDX-License-Identifier: 0BSD
/*
Skill markdown files loaded from config, workspace, and ~/.agents.
Progressive disclosure: catalog (name+description) in the system prefix,
full bodies via load_skill into the transcript.
*/

package skills

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "nullray:constants"
import "nullray:sandbox"

Skill :: struct {
	id:          string,
	name:        string,
	description: string,
	body:        string,
	source:      string,
	path:        string,
}

MAX_SKILLS :: 48
MAX_SKILL_BYTES :: 24_000
MAX_ACTIVE_SKILLS :: 3
MAX_DESCRIPTION_CHARS :: 1024

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

/*
Split optional YAML frontmatter from markdown body.
Returns (meta, body). meta is empty when no frontmatter.
*/
split_frontmatter :: proc(raw: string) -> (meta: string, body: string) {
	text := strings.trim_left_space(raw)
	if !strings.has_prefix(text, "---") {
		return "", raw
	}
	rest := text[3:]
	if len(rest) > 0 && (rest[0] == '\n' || rest[0] == '\r') {
		if rest[0] == '\r' && len(rest) > 1 && rest[1] == '\n' {
			rest = rest[2:]
		} else {
			rest = rest[1:]
		}
	} else {
		return "", raw
	}
	end := strings.index(rest, "\n---")
	if end < 0 {
		return "", raw
	}
	meta = rest[:end]
	after := rest[end + 4:]
	if len(after) > 0 && after[0] == '\n' {
		after = after[1:]
	} else if len(after) > 1 && after[0] == '\r' && after[1] == '\n' {
		after = after[2:]
	}
	return meta, strings.trim_left_space(after)
}

/*
Parse name and description from simple YAML frontmatter.
Supports single-line values and folded description: > blocks.
*/
parse_frontmatter_fields :: proc(
	meta: string,
	allocator := context.allocator,
) -> (name: string, description: string) {
	if len(meta) == 0 {
		return "", ""
	}
	lines := strings.split_lines(meta, context.temp_allocator)
	i := 0
	for i < len(lines) {
		line := lines[i]
		trimmed := strings.trim_space(line)
		if len(trimmed) == 0 || strings.has_prefix(trimmed, "#") {
			i += 1
			continue
		}
		colon := strings.index_byte(line, ':')
		if colon < 0 {
			i += 1
			continue
		}
		key := strings.trim_space(line[:colon])
		val := strings.trim_space(line[colon + 1:])
		key_l := strings.to_lower(key, context.temp_allocator)
		if key_l == "name" {
			if len(val) >= 2 && ((val[0] == '"' && val[len(val) - 1] == '"') || (val[0] == '\'' && val[len(val) - 1] == '\'')) {
				val = val[1:len(val) - 1]
			}
			delete(name)
			name = strings.clone(val, allocator)
			i += 1
			continue
		}
		if key_l == "description" {
			delete(description)
			if val == ">" || val == "|" {
				b: strings.Builder
				strings.builder_init(&b, context.temp_allocator)
				i += 1
				first := true
				for i < len(lines) {
					next := lines[i]
					if len(next) > 0 && (next[0] != ' ' && next[0] != '\t') {
						break
					}
					part := strings.trim_left_space(next)
					if !first {
						strings.write_byte(&b, ' ')
					}
					first = false
					strings.write_string(&b, part)
					i += 1
				}
				description = strings.clone(strings.to_string(b), allocator)
				continue
			}
			if len(val) >= 2 && ((val[0] == '"' && val[len(val) - 1] == '"') || (val[0] == '\'' && val[len(val) - 1] == '\'')) {
				val = val[1:len(val) - 1]
			}
			description = strings.clone(val, allocator)
			i += 1
			continue
		}
		i += 1
	}
	if len(description) > MAX_DESCRIPTION_CHARS {
		trimmed := strings.clone(description[:MAX_DESCRIPTION_CHARS], allocator)
		delete(description)
		description = trimmed
	}
	return name, description
}

load_skill_file :: proc(path, id, source: string, allocator := context.allocator) -> (Skill, bool) {
	data, derr := os.read_entire_file(path, allocator)
	if derr != nil || len(data) == 0 {
		return {}, false
	}
	raw := string(data)
	meta, body_text := split_frontmatter(raw)
	fm_name, fm_desc := parse_frontmatter_fields(meta, allocator)

	body_owned: string
	if meta == "" {
		body_owned = raw
	} else {
		body_owned = strings.clone(body_text, allocator)
		delete(data)
	}
	if len(body_owned) > MAX_SKILL_BYTES {
		trimmed := strings.clone(body_owned[:MAX_SKILL_BYTES], allocator)
		delete(body_owned)
		body_owned = trimmed
	}

	display := fm_name
	if len(display) == 0 {
		tmp, _ := strings.replace_all(id, "-", " ", context.temp_allocator)
		tmp, _ = strings.replace_all(tmp, "_", " ", context.temp_allocator)
		display = strings.clone(tmp, allocator)
	}
	desc := fm_desc
	if len(desc) == 0 {
		desc = strings.clone(display, allocator)
	}

	return Skill{
		id = strings.clone(id, allocator),
		name = display,
		description = desc,
		body = body_owned,
		source = strings.clone(source, allocator),
		path = strings.clone(path, allocator),
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
		flat, _ := load_dir(root, allocator)
		for s in flat {
			if ids[s.id] || len(skills) >= MAX_SKILLS {
				skill_destroy(s)
				continue
			}
			ids[s.id] = true
			append(&skills, s)
		}
		delete(flat)

		if len(skills) >= MAX_SKILLS {
			break
		}

		nested := load_nested_skill_md(root, allocator)
		for s in nested {
			if ids[s.id] || len(skills) >= MAX_SKILLS {
				skill_destroy(s)
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

/*
Tier-1 catalog for the system prefix. Bodies are not included.
*/
render_catalog :: proc(skills: []Skill, allocator := context.allocator) -> string {
	if len(skills) == 0 {
		return ""
	}
	b: strings.Builder
	strings.builder_init(&b, allocator)
	strings.write_string(&b, fmt.tprintf(
		"%d skills available. Call load_skill with an id when the task matches. Bodies are not preloaded.\n\n",
		len(skills),
	))
	for s in skills {
		strings.write_string(&b, "- ")
		strings.write_string(&b, s.id)
		strings.write_string(&b, ": ")
		desc := s.description
		if len(desc) == 0 {
			desc = s.name
		}
		strings.write_string(&b, desc)
		strings.write_byte(&b, '\n')
	}
	return strings.to_string(b)
}

// Deprecated name kept for callers: now renders catalog only.
render_system_prompt :: proc(skills: []Skill, allocator := context.allocator) -> string {
	return render_catalog(skills, allocator)
}

find_by_id :: proc(skills: []Skill, id: string) -> (Skill, bool) {
	for s in skills {
		if s.id == id {
			return s, true
		}
	}
	return {}, false
}

/*
List reference files under the skill's references/ directory when present.
*/
skill_reference_paths :: proc(s: Skill, allocator := context.allocator) -> []string {
	if len(s.path) == 0 {
		return {}
	}
	dir := filepath.dir(s.path)
	refs, jerr := filepath.join({dir, "references"}, context.temp_allocator)
	if jerr != nil {
		return {}
	}
	info, err := os.stat(refs, context.temp_allocator)
	if err != nil || info.type != .Directory {
		return {}
	}
	entries, rerr := os.read_all_directory_by_path(refs, context.temp_allocator)
	if rerr != nil {
		return {}
	}
	out := make([dynamic]string, allocator)
	for e in entries {
		if e.type == .Directory {
			continue
		}
		p, perr := filepath.join({refs, e.name}, allocator)
		if perr == nil {
			append(&out, p)
		}
	}
	return out[:]
}

/*
Format a skill body for injection into the transcript (tool result or auto note).
*/
format_skill_payload :: proc(s: Skill, via: string, allocator := context.allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	strings.write_string(&b, fmt.tprintf("Skill loaded (%s): %s\n\n", via, s.id))
	strings.write_string(&b, s.body)
	refs := skill_reference_paths(s, context.temp_allocator)
	if len(refs) > 0 {
		strings.write_string(&b, "\n\nReferences (read with read_file when needed):\n")
		for r in refs {
			strings.write_string(&b, "- ")
			strings.write_string(&b, r)
			strings.write_byte(&b, '\n')
		}
	}
	return strings.to_string(b)
}

/*
Deterministic match of user text against skill id, name, and description keywords.
Returns up to max_n skill ids (cloned). Caller deletes them.
*/
match_skills :: proc(
	skills: []Skill,
	user_text: string,
	max_n := MAX_ACTIVE_SKILLS,
	allocator := context.allocator,
) -> [dynamic]string {
	out := make([dynamic]string, allocator)
	if max_n <= 0 || len(user_text) == 0 || len(skills) == 0 {
		return out
	}
	lower := strings.to_lower(user_text, context.temp_allocator)
	Score_Hit :: struct {
		id:    string,
		score: int,
	}
	scored := make([dynamic]Score_Hit, context.temp_allocator)

	for s in skills {
		score := 0
		id_l := strings.to_lower(s.id, context.temp_allocator)
		if strings.contains(lower, id_l) {
			score += 5
		}
		name_l := strings.to_lower(s.name, context.temp_allocator)
		if len(name_l) > 2 && strings.contains(lower, name_l) {
			score += 4
		}
		desc_l := strings.to_lower(s.description, context.temp_allocator)
		tokens := strings.fields(desc_l, context.temp_allocator)
		for tok in tokens {
			if len(tok) < 4 {
				continue
			}
			if strings.contains(lower, tok) {
				score += 1
			}
		}
		// Hyphen/underscore pieces of id
		parts := strings.split(id_l, "-", context.temp_allocator)
		for p in parts {
			if len(p) >= 4 && strings.contains(lower, p) {
				score += 2
			}
		}
		if score > 0 {
			append(&scored, Score_Hit{id = s.id, score = score})
		}
	}

	// Simple selection sort by score descending
	for i in 0 ..< len(scored) {
		best := i
		for j in i + 1 ..< len(scored) {
			if scored[j].score > scored[best].score {
				best = j
			}
		}
		scored[i], scored[best] = scored[best], scored[i]
	}

	for i in 0 ..< len(scored) {
		if len(out) >= max_n {
			break
		}
		append(&out, strings.clone(scored[i].id, allocator))
	}
	return out
}

skill_destroy :: proc(s: Skill) {
	delete(s.id)
	delete(s.name)
	delete(s.description)
	delete(s.body)
	delete(s.source)
	delete(s.path)
}

skills_destroy :: proc(skills: ^[dynamic]Skill) {
	for s in skills {
		skill_destroy(s)
	}
	delete(skills^)
	skills^ = {}
}
