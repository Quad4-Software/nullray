// SPDX-License-Identifier: 0BSD
/*
Whitespace normalization for fuzzy patch compare (not for write-back).
*/

package patch

import "core:strings"

TAB_WIDTH :: 4

/*
Normalize line endings and internal whitespace for comparison only.
Caller owns returned string.
*/
normalize_for_compare :: proc(s: string, allocator := context.allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	col := 0
	i := 0
	for i < len(s) {
		c := s[i]
		if c == '\r' {
			if i + 1 < len(s) && s[i + 1] == '\n' {
				i += 1
			}
			strings.write_byte(&b, '\n')
			col = 0
			i += 1
			continue
		}
		if c == '\t' {
			spaces := TAB_WIDTH - (col % TAB_WIDTH)
			for _ in 0 ..< spaces {
				strings.write_byte(&b, ' ')
				col += 1
			}
			i += 1
			continue
		}
		if c == '\n' {
			strings.write_byte(&b, '\n')
			col = 0
			i += 1
			continue
		}
		if c == ' ' {
			strings.write_byte(&b, ' ')
			col += 1
			i += 1
			for i < len(s) && s[i] == ' ' {
				i += 1
			}
			continue
		}
		strings.write_byte(&b, c)
		col += 1
		i += 1
	}
	return strings.to_string(b)
}

