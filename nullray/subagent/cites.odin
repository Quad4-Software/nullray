// SPDX-License-Identifier: 0BSD
/*
Parse and format locate CITES path:start-end handoff blocks.
*/

package subagent

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strconv"
import "core:strings"
import "nullray:constants"

Cite_Span :: struct {
	path:  string,
	start: int,
	end:   int,
	note:  string,
}

cites_destroy :: proc(items: []Cite_Span, allocator := context.allocator) {
	for c in items {
		delete(c.path, allocator)
		delete(c.note, allocator)
	}
	delete(items, allocator)
}

locate_steps_from_env :: proc() -> int {
	n := constants.DEFAULT_LOCATE_STEPS
	if v, ok := os.lookup_env(constants.ENV_LOCATE_STEPS, context.temp_allocator); ok {
		parsed, pok := strconv.parse_int(strings.trim_space(v))
		if pok && parsed >= 1 {
			n = parsed
		}
	}
	if n > constants.MAX_LOCATE_STEPS {
		n = constants.MAX_LOCATE_STEPS
	}
	return n
}

locate_parallel_from_env :: proc() -> int {
	n := constants.DEFAULT_LOCATE_PARALLEL
	if v, ok := os.lookup_env(constants.ENV_LOCATE_PARALLEL, context.temp_allocator); ok {
		parsed, pok := strconv.parse_int(strings.trim_space(v))
		if pok && parsed >= 1 {
			n = parsed
		}
	}
	if n > constants.MAX_LOCATE_PARALLEL {
		n = constants.MAX_LOCATE_PARALLEL
	}
	return n
}

locate_max_cites_from_env :: proc() -> int {
	n := constants.DEFAULT_LOCATE_MAX_CITES
	if v, ok := os.lookup_env(constants.ENV_LOCATE_MAX_CITES, context.temp_allocator); ok {
		parsed, pok := strconv.parse_int(strings.trim_space(v))
		if pok && parsed >= 1 {
			n = parsed
		}
	}
	if n > constants.MAX_LOCATE_MAX_CITES {
		n = constants.MAX_LOCATE_MAX_CITES
	}
	return n
}

is_locate_type :: proc(type_name: string) -> bool {
	low := strings.to_lower(strings.trim_space(type_name), context.temp_allocator)
	return low == "locate" || low == "locate-agent"
}

/*
Parse CITES spans from locate agent text. Prefers path:start-end lines.
Returns owned spans. trailer_none is true when CITES: none appears.
*/
parse_cites_list :: proc(
	text: string,
	max_cites := 0,
	allocator := context.allocator,
) -> (items: []Cite_Span, trailer_none: bool) {
	cap_n := max_cites
	if cap_n <= 0 {
		cap_n = locate_max_cites_from_env()
	}
	out := make([dynamic]Cite_Span, allocator)
	lines := strings.split_lines(text, context.temp_allocator)
	for line in lines {
		trimmed := strings.trim_space(line)
		if len(trimmed) == 0 {
			continue
		}
		lower := strings.to_lower(trimmed, context.temp_allocator)
		if strings.has_prefix(lower, "cites:") {
			rest := strings.trim_space(trimmed[len("cites:"):])
			low_rest := strings.to_lower(rest, context.temp_allocator)
			if low_rest == "none" || low_rest == "0" {
				trailer_none = true
			}
			continue
		}
		path, start, end, note, ok := parse_cite_line(trimmed)
		if !ok {
			continue
		}
		append(
			&out,
			Cite_Span{
				path = strings.clone(path, allocator),
				start = start,
				end = end,
				note = strings.clone(note, allocator),
			},
		)
	}
	if len(out) > 1 {
		slice.sort_by(out[:], proc(a, b: Cite_Span) -> bool {
			if a.path != b.path {
				return a.path < b.path
			}
			return a.start < b.start
		})
	}
	if len(out) > cap_n {
		for i in cap_n ..< len(out) {
			delete(out[i].path, allocator)
			delete(out[i].note, allocator)
		}
		resize(&out, cap_n)
	}
	shrink(&out)
	items = out[:]
	out = {}
	return items, trailer_none
}

parse_cite_line :: proc(line: string) -> (path: string, start, end: int, note: string, ok: bool) {
	trimmed := strings.trim_space(line)
	if len(trimmed) < 3 {
		return
	}
	body := trimmed
	note = ""
	// Optional trailing note after whitespace following the range.
	if sp := strings.index_any(body, " \t"); sp > 0 {
		maybe := body[:sp]
		if cite_has_line_range(maybe) {
			note = strings.trim_space(body[sp + 1:])
			body = maybe
		}
	}
	colon := cite_range_colon(body)
	if colon < 0 {
		return
	}
	path = strings.trim_space(body[:colon])
	range_s := strings.trim_space(body[colon + 1:])
	if len(path) == 0 || len(range_s) == 0 {
		return
	}
	path = cite_normalize_path(path)
	if !cite_path_ok(path) {
		return
	}
	dash := strings.index_byte(range_s, '-')
	if dash < 0 {
		n, nok := strconv.parse_int(range_s)
		if !nok || n < 1 {
			return
		}
		start = n
		end = n
		ok = true
		return
	}
	left := strings.trim_space(range_s[:dash])
	right := strings.trim_space(range_s[dash + 1:])
	n1, ok1 := strconv.parse_int(left)
	n2, ok2 := strconv.parse_int(right)
	if !ok1 || !ok2 || n1 < 1 || n2 < n1 {
		return
	}
	start = n1
	end = n2
	ok = true
	return
}

@(private)
cite_has_line_range :: proc(s: string) -> bool {
	return cite_range_colon(s) >= 0
}

@(private)
cite_range_colon :: proc(s: string) -> int {
	// Last colon followed by a digit starts the line range (skips Windows drive C:).
	best := -1
	for i in 0 ..< len(s) {
		if s[i] != ':' {
			continue
		}
		if i + 1 >= len(s) {
			continue
		}
		c := s[i + 1]
		if c < '0' || c > '9' {
			continue
		}
		best = i
	}
	return best
}

@(private)
cite_normalize_path :: proc(path: string) -> string {
	p := strings.trim_space(path)
	for strings.has_prefix(p, "./") {
		p = p[2:]
	}
	rep, _ := strings.replace_all(p, "\\", "/", context.temp_allocator)
	return rep
}

@(private)
cite_path_ok :: proc(path: string) -> bool {
	if len(path) == 0 {
		return false
	}
	if strings.contains(path, "..") {
		return false
	}
	if path[0] == '/' {
		return false
	}
	if len(path) >= 2 && path[1] == ':' {
		// Absolute Windows path (C:/...).
		return false
	}
	clean, cerr := filepath.clean(path, context.temp_allocator)
	if cerr == nil && filepath.is_abs(clean) {
		return false
	}
	return true
}

format_cites_block :: proc(items: []Cite_Span, allocator := context.allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	if len(items) == 0 {
		strings.write_string(&b, "CITES: none\n")
		return strings.to_string(b)
	}
	fmt.sbprintf(&b, "CITES: %d\n", len(items))
	for c in items {
		if c.start == c.end {
			fmt.sbprintf(&b, "%s:%d\n", c.path, c.start)
		} else {
			fmt.sbprintf(&b, "%s:%d-%d\n", c.path, c.start, c.end)
		}
	}
	return strings.to_string(b)
}

/*
Rewrite locate child text into a parent-facing CITES block.
Soft-fails to CITES: 0 plus a short note when no spans parse.
*/
format_locate_summary :: proc(raw: string, allocator := context.allocator) -> string {
	items, trailer_none := parse_cites_list(raw, 0, allocator)
	defer cites_destroy(items, allocator)
	if len(items) > 0 {
		return format_cites_block(items, allocator)
	}
	if trailer_none {
		return strings.clone("CITES: none\n", allocator)
	}
	note := strings.trim_space(raw)
	if len(note) > 200 {
		note = note[:200]
	}
	flat, _ := strings.replace_all(note, "\n", " ", context.temp_allocator)
	note = flat
	if len(note) == 0 {
		return strings.clone("CITES: 0\n", allocator)
	}
	return fmt.aprintf("CITES: 0\nparse_note: %s\n", note, allocator = allocator)
}
