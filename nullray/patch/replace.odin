// SPDX-License-Identifier: 0BSD
/*
Replace a raw line window [start_line, end_line) with new_text.
*/

package patch

import "core:strings"

/*
Caller owns returned string.
*/
replace_line_window :: proc(
	hay: string,
	start_line, end_line: int,
	new_text: string,
	allocator := context.allocator,
) -> string {
	raw_lines := strings.split_lines(hay, context.temp_allocator)
	if start_line < 0 || end_line > len(raw_lines) || start_line > end_line {
		return strings.clone(hay, allocator)
	}

	parts := make([dynamic]string, context.temp_allocator)
	for i in 0 ..< start_line {
		append(&parts, raw_lines[i])
	}
	if len(new_text) > 0 {
		new_parts := strings.split_lines(new_text, context.temp_allocator)
		trailing := strings.has_suffix(new_text, "\n")
		limit := len(new_parts)
		if trailing && limit > 0 && len(new_parts[limit - 1]) == 0 {
			limit -= 1
		}
		for i in 0 ..< limit {
			append(&parts, new_parts[i])
		}
	}
	for i in end_line ..< len(raw_lines) {
		append(&parts, raw_lines[i])
	}

	b: strings.Builder
	strings.builder_init(&b, allocator)
	for p, i in parts {
		if i > 0 {
			strings.write_byte(&b, '\n')
		}
		strings.write_string(&b, p)
	}
	had_trailing := len(hay) > 0 && (hay[len(hay) - 1] == '\n')
	new_trailing := len(new_text) > 0 && strings.has_suffix(new_text, "\n")
	if had_trailing || (end_line == len(raw_lines) && new_trailing) {
		if len(parts) == 0 || !strings.has_suffix(strings.to_string(b), "\n") {
			out := strings.to_string(b)
			if len(out) == 0 || out[len(out) - 1] != '\n' {
				strings.write_byte(&b, '\n')
			}
		}
	}
	return strings.to_string(b)
}
