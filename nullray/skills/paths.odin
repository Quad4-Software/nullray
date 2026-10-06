// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Path-scoped skill injection. SKILL.md frontmatter paths: globs auto-load
the skill body when a matching file is touched, reusing recall.path glob
rules (os.match, basename, **).
*/

package skills

import "core:os"
import "core:strings"

parse_frontmatter_paths :: proc(meta: string, allocator := context.allocator) -> []string {
	if len(meta) == 0 {
		return nil
	}
	lines := strings.split_lines(meta, context.temp_allocator)
	out := make([dynamic]string, allocator)
	i := 0
	for i < len(lines) {
		line := lines[i]
		colon := strings.index_byte(line, ':')
		if colon < 0 {
			i += 1
			continue
		}
		key := strings.to_lower(strings.trim_space(line[:colon]), context.temp_allocator)
		if key != "paths" {
			i += 1
			continue
		}
		val := strings.trim_space(line[colon + 1:])
		if len(val) > 0 {
			if val[0] == '[' && strings.has_suffix(val, "]") {
				inner := strings.trim_space(val[1:len(val) - 1])
				for part in strings.split(inner, ",", context.temp_allocator) {
					p := strings.trim_space(part)
					p = strings.trim(p, `"'`)
					if len(p) > 0 {
						append(&out, strings.clone(p, allocator))
					}
				}
			} else {
				for part in strings.split(val, ",", context.temp_allocator) {
					p := strings.trim_space(part)
					p = strings.trim(p, `"'`)
					if len(p) > 0 {
						append(&out, strings.clone(p, allocator))
					}
				}
			}
			i += 1
			continue
		}
		i += 1
		for i < len(lines) {
			next := strings.trim_space(lines[i])
			if strings.has_prefix(next, "- ") {
				p := strings.trim_space(next[2:])
				p = strings.trim(p, `"'`)
				if len(p) > 0 {
					append(&out, strings.clone(p, allocator))
				}
				i += 1
				continue
			}
			break
		}
	}
	return out[:]
}

skill_path_matches :: proc(pattern, path: string) -> bool {
	if len(pattern) == 0 || len(path) == 0 {
		return false
	}
	if strings.contains(pattern, "**") {
		parts := strings.split(pattern, "**", context.temp_allocator)
		pos := 0
		for part in parts {
			if len(part) == 0 {
				continue
			}
			idx := strings.index(path[pos:], part)
			if idx < 0 {
				return false
			}
			pos += idx + len(part)
		}
		last := parts[len(parts) - 1]
		if len(last) > 0 && !strings.has_suffix(pattern, "**") && !strings.has_suffix(path, last) {
			return false
		}
		return true
	}
	if matched, err := os.match(pattern, path); err == nil && matched {
		return true
	}
	if !strings.contains(pattern, "/") {
		base := path
		if idx := strings.last_index_any(path, "/\\"); idx >= 0 {
			base = path[idx + 1:]
		}
		if matched, err := os.match(pattern, base); err == nil && matched {
			return true
		}
	}
	return false
}

skill_matches_path :: proc(sk: Skill, path: string) -> bool {
	for p in sk.paths {
		if skill_path_matches(p, path) {
			return true
		}
	}
	return false
}

notes_for_path :: proc(path: string, allocator := context.allocator) -> string {
	if len(path) == 0 {
		return ""
	}
	loaded, _ := load_default(allocator)
	defer skills_destroy(&loaded)
	b: strings.Builder
	strings.builder_init(&b, allocator)
	n := 0
	for sk in loaded {
		if n >= MAX_ACTIVE_SKILLS {
			break
		}
		if skill_matches_path(sk, path) {
			strings.write_string(&b, format_skill_payload(sk, "path", context.temp_allocator))
			strings.write_byte(&b, '\n')
			n += 1
		}
	}
	if n == 0 {
		strings.builder_destroy(&b)
		return ""
	}
	return strings.to_string(b)
}
