// SPDX-License-Identifier: 0BSD
/*
Parse compiler/linter diagnostics from verify command output.
*/

package agent

import "core:fmt"
import "core:strconv"
import "core:strings"
import "nullray:constants"

Finding :: struct {
	path:     string,
	line:     int,
	col:      int,
	severity: string,
	msg:      string,
}

delete_findings :: proc(findings: ^[dynamic]Finding) {
	for f in findings {
		delete(f.path)
		delete(f.severity)
		delete(f.msg)
	}
	delete(findings^)
}

@(private)
finding_key :: proc(f: Finding, allocator := context.temp_allocator) -> string {
	return fmt.aprintf("%s:%d:%s", f.path, f.line, f.msg, allocator = allocator)
}

@(private)
append_finding :: proc(
	out: ^[dynamic]Finding,
	seen: ^map[string]bool,
	path: string,
	line, col: int,
	sev, msg: string,
	allocator := context.allocator,
) {
	if len(out) >= constants.MAX_VERIFY_FINDINGS {
		return
	}
	p := strings.clone(strings.trim_space(path), allocator)
	m_src := strings.trim_space(msg)
	m: string
	if len(m_src) > 160 {
		m = strings.clone(m_src[:160], allocator)
	} else {
		m = strings.clone(m_src, allocator)
	}
	f := Finding{
		path = p,
		line = line,
		col = col,
		severity = strings.clone(sev, allocator),
		msg = m,
	}
	key := finding_key(f)
	if seen[key] {
		delete(f.path)
		delete(f.severity)
		delete(f.msg)
		return
	}
	seen[key] = true
	append(out, f)
}

@(private)
parse_line_col_path :: proc(line: string) -> (path: string, ln, col: int, rest: string, ok: bool) {
	trimmed := strings.trim_space(line)
	if len(trimmed) < 5 {
		return
	}
	body := trimmed
	if strings.has_prefix(body, "--> ") {
		body = strings.trim_space(body[4:])
	}
	if lp := strings.index(body, "("); lp > 0 {
		rp := strings.index(body[lp:], ")")
		if rp > 0 {
			inside := body[lp + 1:lp + rp]
			if strings.contains(inside, ",") {
				parts := strings.split(inside, ",", context.temp_allocator)
				if len(parts) >= 2 {
					n1, ok1 := strconv.parse_int(strings.trim_space(parts[0]))
					n2, _ := strconv.parse_int(strings.trim_space(parts[1]))
					if ok1 && n1 > 0 {
						path = body[:lp]
						ln = n1
						col = n2
						rest = strings.trim_space(body[lp + rp + 1:])
						if strings.has_prefix(rest, ":") {
							rest = strings.trim_space(rest[1:])
						}
						ok = true
						return
					}
				}
			} else {
				parts := strings.split(inside, ":", context.temp_allocator)
				if len(parts) >= 1 {
					n1, ok1 := strconv.parse_int(parts[0])
					n2 := 0
					if len(parts) >= 2 {
						n2, _ = strconv.parse_int(parts[1])
					}
					if ok1 && n1 > 0 {
						path = body[:lp]
						ln = n1
						col = n2
						rest = strings.trim_space(body[lp + rp + 1:])
						ok = true
						return
					}
				}
			}
		}
	}
	colon1 := strings.index(body, ":")
	if colon1 <= 0 {
		return
	}
	if colon1 == 1 && len(body) > 2 && (body[2] == '\\' || body[2] == '/') {
		rest_body := body[2:]
		c2 := strings.index(rest_body, ":")
		if c2 < 0 {
			return
		}
		colon1 = 2 + c2
	}
	after := body[colon1 + 1:]
	colon2 := strings.index(after, ":")
	if colon2 < 0 {
		return
	}
	line_s := after[:colon2]
	n1, ok1 := strconv.parse_int(line_s)
	if !ok1 || n1 <= 0 {
		return
	}
	after2 := after[colon2 + 1:]
	colon3 := strings.index(after2, ":")
	n2 := 0
	msg := after2
	if colon3 >= 0 {
		col_s := after2[:colon3]
		if n, ok2 := strconv.parse_int(col_s); ok2 {
			n2 = n
			msg = after2[colon3 + 1:]
		}
	}
	path = body[:colon1]
	ln = n1
	col = n2
	rest = strings.trim_space(msg)
	ok = true
	return
}

/*
Extract up to MAX_VERIFY_FINDINGS diagnostics. Caller owns findings.
*/
parse_diagnostics :: proc(output: string, allocator := context.allocator) -> [dynamic]Finding {
	out := make([dynamic]Finding, allocator)
	seen := make(map[string]bool, context.temp_allocator)
	lines := strings.split_lines(output, context.temp_allocator)
	for line in lines {
		lower := strings.to_lower(line, context.temp_allocator)
		sev := "error"
		if strings.contains(lower, "warning") {
			sev = "warn"
		}
		interesting :=
			strings.contains(lower, "error") ||
			strings.contains(lower, "warning") ||
			strings.has_prefix(strings.trim_space(line), "-->") ||
			(strings.contains(line, "(") && strings.contains(line, ")"))
		if !interesting && !strings.contains(line, ":") {
			continue
		}
		path, ln, col, rest, ok := parse_line_col_path(line)
		if !ok {
			continue
		}
		if len(rest) == 0 {
			rest = "error"
		}
		if !interesting && !strings.contains(strings.to_lower(rest, context.temp_allocator), "error") {
			continue
		}
		append_finding(&out, &seen, path, ln, col, sev, rest, allocator)
	}
	return out
}

format_findings_block :: proc(findings: []Finding, allocator := context.allocator) -> string {
	if len(findings) == 0 {
		return ""
	}
	b: strings.Builder
	strings.builder_init(&b, allocator)
	strings.write_string(&b, "Fix these errors:\n")
	for f, i in findings {
		if f.col > 0 {
			fmt.sbprintf(&b, "%d. %s:%d:%d %s\n", i + 1, f.path, f.line, f.col, f.msg)
		} else {
			fmt.sbprintf(&b, "%d. %s:%d %s\n", i + 1, f.path, f.line, f.msg)
		}
	}
	return strings.to_string(b)
}
