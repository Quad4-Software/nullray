// SPDX-License-Identifier: 0BSD
/*
Short LID-safe failure hints for patch apply.
*/

package patch

import "core:fmt"
import "core:math"
import "core:path/filepath"
import "core:strings"

HINT_MAX :: 400

/*
Build a capped not-found / ambiguous hint. Caller owns returned string.
*/
format_hint :: proc(
	path, reason, content, old_string: string,
	allocator := context.allocator,
) -> string {
	base := filepath.base(path)
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	fmt.sbprintf(&b, "old_string not found in %s: %s", base, reason)

	if len(old_string) > 0 && len(content) > 0 {
		hit, kind := fuzzy_find(content, old_string)
		if kind == .Fuzzy || kind == .Ambiguous {
			lines := strings.split_lines(content, context.temp_allocator)
			start := hit.start_line
			end := math.min(hit.end_line, len(lines))
			n := 0
			for i in start ..< end {
				if n >= 2 {
					break
				}
				snip := strings.trim_right_space(lines[i])
				if len(snip) > 80 {
					snip = snip[:80]
				}
				fmt.sbprintf(&b, "\n~%d:%s", i + 1, snip)
				n += 1
			}
		} else {
			needle := strings.trim_space(old_string)
			if len(needle) > 24 {
				needle = needle[:24]
			}
			lines := strings.split_lines(content, context.temp_allocator)
			shown := 0
			for line, i in lines {
				if shown >= 2 {
					break
				}
				prefix_n := math.min(12, len(needle))
				if len(needle) > 0 && strings.contains(line, needle[:prefix_n]) {
					snip := strings.trim_right_space(line)
					if len(snip) > 80 {
						snip = snip[:80]
					}
					fmt.sbprintf(&b, "\n~%d:%s", i + 1, snip)
					shown += 1
				}
			}
		}
	}

	out := strings.to_string(b)
	if len(out) > HINT_MAX {
		return strings.clone(out[:HINT_MAX], allocator)
	}
	return strings.clone(out, allocator)
}
