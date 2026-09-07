// SPDX-License-Identifier: 0BSD
/*
compact_context tool: model-requested phase-end compaction hint.
*/

package tools

import "core:strings"

tool_compact_context :: proc(args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	_ = args_json
	return strings.clone(
		"compact_context: acknowledged. Harness will clear stale tool results on the next prepare step. Prefer this when switching from explore to edit.",
		allocator,
	), ""
}
