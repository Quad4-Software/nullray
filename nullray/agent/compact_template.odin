// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Fielded compaction template. Freeform summaries drop state under high
compression. The headings below are the recall surface for later turns.
*/

package agent

import "core:strings"

COMPACT_TEMPLATE_INTRO :: "Summarize this coding-agent conversation for future context. Use exactly these headings, one short paragraph each. Write empty if unknown.\n\nGoal:\nFiles:\nErrors:\nNext:\nPending steers:\n\n"

COMPACT_HEADING_GOAL :: "Goal:"
COMPACT_HEADING_FILES :: "Files:"
COMPACT_HEADING_ERRORS :: "Errors:"
COMPACT_HEADING_NEXT :: "Next:"
COMPACT_HEADING_STEERS :: "Pending steers:"

compact_has_headings :: proc(text: string) -> bool {
	return strings.contains(text, COMPACT_HEADING_GOAL) &&
		strings.contains(text, COMPACT_HEADING_FILES) &&
		strings.contains(text, COMPACT_HEADING_ERRORS) &&
		strings.contains(text, COMPACT_HEADING_NEXT)
}

format_compact_fields :: proc(raw: string, allocator := context.allocator) -> string {
	src := strings.trim_space(raw)
	if len(src) == 0 {
		return strings.clone(
			"Goal:\n(unknown)\nFiles:\n(none)\nErrors:\n(none)\nNext:\n(unknown)\nPending steers:\n(none)",
			allocator,
		)
	}
	if compact_has_headings(src) {
		if !strings.contains(src, COMPACT_HEADING_STEERS) {
			return strings.concatenate({src, "\nPending steers:\n(none)"}, allocator)
		}
		return strings.clone(src, allocator)
	}
	return strings.concatenate(
		{
			"Goal:\n",
			src,
			"\nFiles:\n(see transcript)\nErrors:\n(see transcript)\nNext:\n(continue)\nPending steers:\n(none)",
		},
		allocator,
	)
}
