// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Minimal TOML and YAML readers for foreign tool configs. These are line
scanners for the few scalars, tables, and list blocks each tool stores - not
general parsers.
*/

package config

import "core:strings"

unquote :: proc(v: string) -> string {
	s := strings.trim_space(v)
	if len(s) >= 2 {
		if (s[0] == '"' && s[len(s) - 1] == '"') || (s[0] == '\'' && s[len(s) - 1] == '\'') {
			return s[1:len(s) - 1]
		}
	}
	return s
}

// Bare or quoted scalar value for key = value in TOML text.
toml_value_in :: proc(body, key: string) -> string {
	for raw in strings.split_lines(body, context.temp_allocator) {
		line := strings.trim_space(raw)
		if len(line) == 0 || strings.has_prefix(line, "#") || strings.has_prefix(line, "[") {
			continue
		}
		eq := strings.index_byte(line, '=')
		if eq <= 0 {
			continue
		}
		if strings.trim_space(line[:eq]) != key {
			continue
		}
		val := strings.trim_space(line[eq + 1:])
		if idx := strings.index(val, " #"); idx >= 0 {
			val = strings.trim_space(val[:idx])
		}
		return unquote(val)
	}
	return ""
}

// Lines above the first [section] header, for top-level keys.
toml_root :: proc(body: string) -> string {
	lines := strings.split_lines(body, context.temp_allocator)
	for line, i in lines {
		if strings.has_prefix(strings.trim_space(line), "[") {
			return strings.join(lines[:i], "\n", context.temp_allocator)
		}
	}
	return body
}

// Collect [prefix.name] sections from TOML text. Returns header names and
// each section's body for toml_value_in.
Foreign_Section :: struct {
	name: string,
	body: string,
}

toml_sections :: proc(body, prefix: string) -> []Foreign_Section {
	out := make([dynamic]Foreign_Section, context.temp_allocator)
	lines := strings.split_lines(body, context.temp_allocator)
	cur_name := ""
	start := -1
	for line, i in lines {
		trim := strings.trim_space(line)
		if strings.has_prefix(trim, "[") {
			if len(cur_name) > 0 {
				append(&out, Foreign_Section{
					name = cur_name,
					body = strings.join(lines[start:i], "\n", context.temp_allocator),
				})
			}
			cur_name = ""
			head := strings.trim(trim, "[]")
			head = strings.trim(head, `"`)
			if strings.has_prefix(head, prefix) && len(head) > len(prefix) && head[len(prefix)] == '.' {
				cur_name = head[len(prefix) + 1:]
			}
			start = i + 1
		}
	}
	if len(cur_name) > 0 {
		append(&out, Foreign_Section{
			name = cur_name,
			body = strings.join(lines[start:], "\n", context.temp_allocator),
		})
	}
	return out[:]
}

@(private)
yaml_col0 :: proc(line: string) -> bool {
	return len(line) > 0 && line[0] != ' ' && line[0] != '\t'
}

// Scalar for a col-0 key: value line. Strips quotes and inline comments.
yaml_scalar :: proc(body, key: string) -> string {
	for raw in strings.split_lines(body, context.temp_allocator) {
		if !yaml_col0(raw) {
			continue
		}
		line := strings.trim_right(raw, " \t")
		if !strings.has_prefix(line, key) {
			continue
		}
		rest := strings.trim_space(line[len(key):])
		if len(rest) == 0 || rest[0] != ':' {
			continue
		}
		val := strings.trim_space(rest[1:])
		if len(val) == 0 || val[0] == '|' || val[0] == '>' {
			return ""
		}
		if idx := strings.index(val, " #"); idx >= 0 {
			val = strings.trim_space(val[:idx])
		}
		return unquote(val)
	}
	return ""
}

// All col-0 KEY: scalar pairs (goose secrets.yaml shape).
yaml_flat_map :: proc(body: string, pairs: ^[dynamic]Env_KV) {
	for raw in strings.split_lines(body, context.temp_allocator) {
		if !yaml_col0(raw) {
			continue
		}
		line := strings.trim_right(raw, " \t")
		idx := strings.index_byte(line, ':')
		if idx <= 0 {
			continue
		}
		key := strings.trim_space(line[:idx])
		val := unquote(strings.trim_space(line[idx + 1:]))
		if len(key) > 0 && len(val) > 0 {
			append(pairs, Env_KV{key = key, val = val})
		}
	}
}

// Text of the indented block under a col-0 key: header.
yaml_block :: proc(body, key: string) -> string {
	lines := strings.split_lines(body, context.temp_allocator)
	start := -1
	for raw, i in lines {
		if !yaml_col0(raw) {
			continue
		}
		trim := strings.trim_space(raw)
		if start >= 0 {
			return strings.join(lines[start:i], "\n", context.temp_allocator)
		}
		if strings.has_prefix(trim, key) {
			rest := strings.trim_space(trim[len(key):])
			if len(rest) > 0 && rest[0] == ':' {
				start = i + 1
			}
		}
	}
	if start >= 0 {
		return strings.join(lines[start:], "\n", context.temp_allocator)
	}
	return ""
}

// Scalar for key: value at any indent inside a block.
yaml_kv_in :: proc(block, key: string) -> string {
	for raw in strings.split_lines(block, context.temp_allocator) {
		trim := strings.trim_space(raw)
		trim = strings.trim_prefix(trim, "- ")
		if !strings.has_prefix(trim, key) {
			continue
		}
		rest := strings.trim_space(trim[len(key):])
		if len(rest) == 0 || rest[0] != ':' {
			continue
		}
		val := strings.trim_space(rest[1:])
		if len(val) == 0 {
			return ""
		}
		if idx := strings.index(val, " #"); idx >= 0 {
			val = strings.trim_space(val[:idx])
		}
		return unquote(val)
	}
	return ""
}

// Split a yaml list block into per-item text (aichat clients:, aider api-key:).
yaml_list_items :: proc(block: string, items: ^[dynamic]string) {
	lines := strings.split_lines(block, context.temp_allocator)
	start := -1
	for raw, i in lines {
		trim := strings.trim_space(raw)
		if strings.has_prefix(trim, "- ") || trim == "-" {
			if start >= 0 {
				append(items, strings.join(lines[start:i], "\n", context.temp_allocator))
			}
			start = i
		}
	}
	if start >= 0 {
		append(items, strings.join(lines[start:], "\n", context.temp_allocator))
	}
}

// Bare scalars from a - value list (aider api-key entries).
yaml_list_scalars :: proc(block: string, out: ^[dynamic]string) {
	for raw in strings.split_lines(block, context.temp_allocator) {
		trim := strings.trim_space(raw)
		if !strings.has_prefix(trim, "-") {
			continue
		}
		val := unquote(strings.trim_space(trim[1:]))
		if len(val) > 0 {
			append(out, val)
		}
	}
}
