// SPDX-License-Identifier: 0BSD
/*
Exact-then-fuzzy search/replace apply for edit tools.
*/

package patch

import "core:strings"

Match_Kind :: enum {
	Exact,
	Fuzzy,
	None,
	Ambiguous,
}

/*
Apply old->new on content. Exact substring first, then fuzzy line-block.
Caller owns updated when err is empty. err is owned on failure.
*/
apply_replace :: proc(
	content, old_string, new_string: string,
	replace_all: bool,
	allocator := context.allocator,
) -> (updated: string, kind: Match_Kind, err: string) {
	if len(old_string) == 0 {
		return "", .None, strings.clone("old_string must be non-empty", allocator)
	}
	if strings.contains(content, old_string) {
		out: string
		if replace_all {
			out, _ = strings.replace_all(content, old_string, new_string, allocator)
		} else {
			out, _ = strings.replace(content, old_string, new_string, 1, allocator)
		}
		return out, .Exact, ""
	}

	hit, fkind := fuzzy_find(content, old_string)
	if fkind == .Ambiguous {
		return "", .Ambiguous, strings.clone("old_string ambiguous (multiple close matches)", allocator)
	}
	if fkind == .None {
		return "", .None, strings.clone("old_string not found", allocator)
	}
	if replace_all {
		return "", .Ambiguous, strings.clone("replace_all requires exact match (fuzzy hit is single-window)", allocator)
	}
	out := replace_line_window(content, hit.start_line, hit.end_line, new_string, allocator)
	return out, .Fuzzy, ""
}
