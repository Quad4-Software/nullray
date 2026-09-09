// SPDX-License-Identifier: 0BSD
package skills

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

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
Catalog lines for list_skills and /skills. Caller deletes the result.
*/
format_list_text :: proc(skills: []Skill, allocator := context.allocator) -> string {
	if len(skills) == 0 {
		return strings.clone("(no skills)", allocator)
	}
	order := make([]int, len(skills), context.temp_allocator)
	for i in 0 ..< len(skills) {
		order[i] = i
	}
	for i in 0 ..< len(order) {
		best := i
		for j in i + 1 ..< len(order) {
			if skills[order[j]].id < skills[order[best]].id {
				best = j
			}
		}
		order[i], order[best] = order[best], order[i]
	}
	b: strings.Builder
	strings.builder_init(&b, allocator)
	for n, i in order {
		if i > 0 {
			strings.write_byte(&b, '\n')
		}
		s := skills[n]
		strings.write_string(&b, s.id)
		strings.write_string(&b, ": ")
		desc := s.description
		if len(desc) == 0 {
			desc = s.name
		}
		strings.write_string(&b, desc)
		if len(s.source) > 0 {
			strings.write_string(&b, "  [")
			strings.write_string(&b, s.source)
			strings.write_byte(&b, ']')
		}
	}
	return strings.to_string(b)
}

/*
One skill for /skills ID. Caller deletes the result.
*/
format_detail_text :: proc(s: Skill, allocator := context.allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	fmt.sbprintf(&b, "id: %s\n", s.id)
	if len(s.name) > 0 {
		fmt.sbprintf(&b, "name: %s\n", s.name)
	}
	desc := s.description
	if len(desc) == 0 {
		desc = s.name
	}
	if len(desc) > 0 {
		fmt.sbprintf(&b, "description: %s\n", desc)
	}
	if len(s.source) > 0 {
		fmt.sbprintf(&b, "source: %s\n", s.source)
	}
	if len(s.path) > 0 {
		fmt.sbprintf(&b, "path: %s\n", s.path)
	}
	if len(s.body) > 0 {
		strings.write_byte(&b, '\n')
		strings.write_string(&b, s.body)
		if s.body[len(s.body) - 1] != '\n' {
			strings.write_byte(&b, '\n')
		}
	}
	return strings.to_string(b)
}

skills_list_text :: proc(allocator := context.allocator) -> string {
	loaded, _ := load_default(allocator)
	defer skills_destroy(&loaded)
	return format_list_text(loaded[:], allocator)
}

skills_show_text :: proc(id: string, allocator := context.allocator) -> (text: string, ok: bool) {
	loaded, _ := load_default(allocator)
	defer skills_destroy(&loaded)
	sk, found := find_by_id(loaded[:], id)
	if !found {
		return "", false
	}
	return format_detail_text(sk, allocator), true
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
	strings.write_string(
		&b,
		"[nullray internal] The following is a skill brief for you (nullray), not a message from the user.\n\n",
	)
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
