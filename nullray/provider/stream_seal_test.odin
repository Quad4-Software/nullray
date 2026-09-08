// SPDX-License-Identifier: 0BSD
package provider

import "core:strings"
import "core:testing"

@(test)
test_stream_seal_waits_for_next_index_not_parsable_json :: proc(t: ^testing.T) {
	a: Stream_Tool_Accum
	stream_tool_accum_init(&a)
	defer stream_tool_accum_destroy(&a)

	sealed := make([dynamic]int, context.allocator)
	defer delete(sealed)

	// Intermediate buffer is valid JSON but must not seal.
	stream_tool_accum_apply(&a, 0, "c0", "read_file", `{"path":"a"}`, &sealed)
	testing.expect(t, len(sealed) == 0)
	testing.expect(t, !a.sealed[0])

	// More args arrive (Vercel-style truncated-prefix trap).
	stream_tool_accum_apply(&a, 0, "", "", `,"offset":"1"}`, &sealed)
	testing.expect(t, len(sealed) == 0)
	testing.expect(t, strings.contains(a.calls[0].arguments, `"offset"`))

	// Next tool index seals prior call with full args.
	stream_tool_accum_apply(&a, 1, "c1", "list_dir", `{"path":"."}`, &sealed)
	testing.expect(t, len(sealed) == 1)
	testing.expect(t, sealed[0] == 0)
	testing.expect(t, a.sealed[0])
	testing.expect(t, !a.sealed[1])
	testing.expect(t, a.calls[0].arguments == `{"path":"a"},"offset":"1"}`)
}

@(test)
test_stream_seal_all_on_finish :: proc(t: ^testing.T) {
	a: Stream_Tool_Accum
	stream_tool_accum_init(&a)
	defer stream_tool_accum_destroy(&a)

	sealed := make([dynamic]int, context.allocator)
	defer delete(sealed)

	stream_tool_accum_apply(&a, 0, "c0", "read_file", `{"path":"x"}`, &sealed)
	testing.expect(t, len(sealed) == 0)

	stream_tool_accum_seal_all(&a, &sealed)
	testing.expect(t, len(sealed) == 1)
	testing.expect(t, sealed[0] == 0)
	testing.expect(t, a.sealed[0])

	clear(&sealed)
	stream_tool_accum_seal_all(&a, &sealed)
	testing.expect(t, len(sealed) == 0)
}
