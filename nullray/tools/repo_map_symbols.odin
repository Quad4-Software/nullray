// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Symbol extraction for repo_map. Cheap regex-style scans, no tree-sitter.
*/

package tools

import "core:os"
import "core:strings"

repo_map_symbol_line :: proc(path, name: string, allocator := context.temp_allocator) -> string {
	low := strings.to_lower(name, context.temp_allocator)
	kind := ""
	switch {
	case strings.has_suffix(low, ".odin"):
		kind = "odin"
	case strings.has_suffix(low, ".go"):
		kind = "go"
	case strings.has_suffix(low, ".py"):
		kind = "py"
	case strings.has_suffix(low, ".rs"):
		kind = "rs"
	case strings.has_suffix(low, ".ts"), strings.has_suffix(low, ".js"), strings.has_suffix(low, ".tsx"), strings.has_suffix(low, ".jsx"):
		kind = "js"
	case:
		return ""
	}
	data, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil || len(data) == 0 {
		return ""
	}
	if len(data) > 64 * 1024 {
		data = data[:64 * 1024]
	}
	syms := repo_map_extract_symbols(kind, string(data), context.temp_allocator)
	if len(syms) == 0 {
		return ""
	}
	b: strings.Builder
	strings.builder_init(&b, allocator)
	strings.write_string(&b, "  [")
	for s, i in syms {
		if i > 0 {
			strings.write_string(&b, ", ")
		}
		if i >= 8 {
			strings.write_string(&b, "...")
			break
		}
		strings.write_string(&b, s)
	}
	strings.write_byte(&b, ']')
	return strings.to_string(b)
}

repo_map_extract_symbols :: proc(kind, src: string, allocator := context.temp_allocator) -> []string {
	out := make([dynamic]string, 0, 8, allocator)
	lines := strings.split_lines(src, context.temp_allocator)
	for line in lines {
		trim := strings.trim_space(line)
		name := ""
		switch kind {
		case "odin":
			name = repo_map_ident_before(trim, " :: proc")
			if len(name) == 0 {
				name = repo_map_ident_before(trim, " :: struct")
			}
			if len(name) == 0 {
				name = repo_map_ident_before(trim, " :: enum")
			}
		case "go":
			if strings.has_prefix(trim, "func ") {
				name = repo_map_go_func(trim[5:])
			} else if strings.has_prefix(trim, "type ") {
				name = repo_map_first_ident(trim[5:])
			}
		case "py":
			if strings.has_prefix(trim, "def ") {
				name = repo_map_first_ident(trim[4:])
			} else if strings.has_prefix(trim, "class ") {
				name = repo_map_first_ident(trim[6:])
			}
		case "rs":
			rest := trim
			if strings.has_prefix(rest, "pub ") {
				rest = strings.trim_space(rest[4:])
			}
			if strings.has_prefix(rest, "fn ") {
				name = repo_map_first_ident(rest[3:])
			} else if strings.has_prefix(rest, "struct ") {
				name = repo_map_first_ident(rest[7:])
			} else if strings.has_prefix(rest, "enum ") {
				name = repo_map_first_ident(rest[5:])
			} else if strings.has_prefix(rest, "impl ") {
				name = repo_map_first_ident(rest[5:])
			}
		case "js":
			if strings.has_prefix(trim, "function ") {
				name = repo_map_first_ident(trim[9:])
			} else if strings.has_prefix(trim, "class ") {
				name = repo_map_first_ident(trim[6:])
			} else if strings.has_prefix(trim, "export function ") {
				name = repo_map_first_ident(trim[len("export function "):])
			}
		}
		if len(name) > 0 && len(out) < 12 {
			append(&out, name)
		}
	}
	return out[:]
}

@(private)
repo_map_ident_before :: proc(line, marker: string) -> string {
	idx := strings.index(line, marker)
	if idx <= 0 {
		return ""
	}
	return repo_map_last_ident(line[:idx])
}

@(private)
repo_map_last_ident :: proc(s: string) -> string {
	end := len(s)
	for end > 0 {
		c := s[end - 1]
		if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' {
			break
		}
		end -= 1
	}
	start := end
	for start > 0 {
		c := s[start - 1]
		if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' {
			start -= 1
			continue
		}
		break
	}
	if start >= end {
		return ""
	}
	return s[start:end]
}

@(private)
repo_map_first_ident :: proc(s: string) -> string {
	i := 0
	for i < len(s) {
		c := s[i]
		if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_' {
			break
		}
		i += 1
	}
	j := i
	for j < len(s) {
		c := s[j]
		if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' {
			j += 1
			continue
		}
		break
	}
	if j <= i {
		return ""
	}
	return s[i:j]
}

@(private)
repo_map_go_func :: proc(after: string) -> string {
	s := strings.trim_space(after)
	if strings.has_prefix(s, "(") {
		rp := strings.index(s, ")")
		if rp < 0 {
			return ""
		}
		s = strings.trim_space(s[rp + 1:])
	}
	return repo_map_first_ident(s)
}
