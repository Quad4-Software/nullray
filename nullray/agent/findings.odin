// SPDX-License-Identifier: 0BSD
/*
Parse review findings into a machine-readable list for CI JSON output.
*/

package agent

import "core:fmt"
import "core:strconv"
import "core:strings"

Review_Finding :: struct {
	severity: string,
	path:     string,
	reason:   string,
	line:     int,
}

findings_destroy :: proc(items: []Review_Finding) {
	for f in items {
		delete(f.severity)
		delete(f.path)
		delete(f.reason)
	}
	delete(items)
}

/*
Extract findings from review text. Prefers SEVERITY|path|reason lines, then
falls back to count from FINDINGS trailer only.
*/
parse_findings_list :: proc(text: string, allocator := context.allocator) -> []Review_Finding {
	out := make([dynamic]Review_Finding, allocator)
	scan := text
	// Auto hunt combines explore + oracle. Only score the oracle section.
	if idx := strings.last_index(text, "--- hunt oracle ---"); idx >= 0 {
		scan = text[idx:]
	}
	lines := strings.split_lines(scan, context.temp_allocator)
	for line in lines {
		trimmed := strings.trim_space(line)
		if len(trimmed) == 0 {
			continue
		}
		lower := strings.to_lower(trimmed, context.temp_allocator)
		if strings.has_prefix(lower, "findings:") {
			continue
		}
		if strings.has_prefix(lower, "--- hunt") {
			continue
		}
		sev, path, reason, line_no, ok := parse_finding_line(trimmed)
		if !ok {
			continue
		}
		append(
			&out,
			Review_Finding{
				severity = strings.clone(sev, allocator),
				path = strings.clone(path, allocator),
				reason = strings.clone(reason, allocator),
				line = line_no,
			},
		)
	}
	return out[:]
}

parse_finding_line :: proc(line: string) -> (sev, path, reason: string, line_no: int, ok: bool) {
	parts, _ := strings.split_n(line, "|", 3, context.temp_allocator)
	if len(parts) < 3 {
		return "", "", "", 0, false
	}
	sev = strings.trim_space(strings.to_lower(parts[0], context.temp_allocator))
	switch sev {
	case "block", "high", "warn", "note", "critical", "major", "medium", "minor", "low", "trivial", "info":
	case:
		return "", "", "", 0, false
	}
	path = strings.trim_space(parts[1])
	reason = strings.trim_space(parts[2])
	if len(path) == 0 || len(reason) == 0 {
		return "", "", "", 0, false
	}
	// path:line form
	if colon := strings.last_index_byte(path, ':'); colon > 0 {
		n, nok := strconv.parse_int(path[colon + 1:])
		if nok && n > 0 {
			line_no = n
			path = path[:colon]
		}
	}
	return sev, path, reason, line_no, true
}

findings_to_json :: proc(items: []Review_Finding, count: int, found: bool, allocator := context.allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	fmt.sbprintf(&b, `{{"count":%d,"trailer_found":%v,"items":[`, count, found)
	for f, i in items {
		if i > 0 {
			strings.write_byte(&b, ',')
		}
		fmt.sbprintf(
			&b,
			`{{"severity":"%s","path":"%s","line":%d,"reason":"%s"}}`,
			json_escape_basic(f.severity, context.temp_allocator),
			json_escape_basic(f.path, context.temp_allocator),
			f.line,
			json_escape_basic(f.reason, context.temp_allocator),
		)
	}
	strings.write_string(&b, "]}")
	return strings.to_string(b)
}

@(private)
json_escape_basic :: proc(s: string, allocator := context.temp_allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	for r in s {
		switch r {
		case '"', '\\':
			strings.write_byte(&b, '\\')
			strings.write_byte(&b, u8(r))
		case '\n':
			strings.write_string(&b, "\\n")
		case '\r':
			strings.write_string(&b, "\\r")
		case '\t':
			strings.write_string(&b, "\\t")
		case:
			strings.write_rune(&b, r)
		}
	}
	return strings.to_string(b)
}
