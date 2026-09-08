// SPDX-License-Identifier: 0BSD
/*
Seal streamed tool_calls indices when the next index appears or the stream ends.
Never seal because partial JSON happens to parse.
*/

package provider

import "core:strings"

Stream_Tool_Accum :: struct {
	calls:  [dynamic]Tool_Call,
	sealed: [dynamic]bool,
}

stream_tool_accum_init :: proc(a: ^Stream_Tool_Accum, allocator := context.allocator) {
	a.calls = make([dynamic]Tool_Call, allocator)
	a.sealed = make([dynamic]bool, allocator)
}

stream_tool_accum_destroy :: proc(a: ^Stream_Tool_Accum) {
	if a == nil {
		return
	}
	for c in a.calls {
		delete(c.id)
		delete(c.name)
		delete(c.arguments)
	}
	delete(a.calls)
	delete(a.sealed)
	a^ = {}
}

/*
Apply one tool_calls delta. Seals every lower index when a higher index is first seen.
Returns newly sealed indices in `out_sealed` (caller provides/clears dynamic).
*/
stream_tool_accum_apply :: proc(
	a: ^Stream_Tool_Accum,
	idx: int,
	id, name, args_frag: string,
	out_sealed: ^[dynamic]int,
	allocator := context.allocator,
) {
	if a == nil || idx < 0 {
		return
	}
	for len(a.calls) <= idx {
		append(&a.calls, Tool_Call{})
		append(&a.sealed, false)
	}
	tc := &a.calls[idx]
	if len(id) > 0 && len(tc.id) == 0 {
		tc.id = strings.clone(id, allocator)
	}
	if len(name) > 0 && len(tc.name) == 0 {
		tc.name = strings.clone(name, allocator)
	}
	if len(args_frag) > 0 {
		old := tc.arguments
		tc.arguments = strings.concatenate({tc.arguments, args_frag}, allocator)
		delete(old)
	}
	for j in 0 ..< idx {
		if j < len(a.sealed) && !a.sealed[j] {
			a.sealed[j] = true
			if out_sealed != nil {
				append(out_sealed, j)
			}
		}
	}
}

/*
Seal every unsealed index. Returns newly sealed indices.
*/
stream_tool_accum_seal_all :: proc(a: ^Stream_Tool_Accum, out_sealed: ^[dynamic]int) {
	if a == nil {
		return
	}
	for i in 0 ..< len(a.calls) {
		if i < len(a.sealed) && !a.sealed[i] {
			a.sealed[i] = true
			if out_sealed != nil {
				append(out_sealed, i)
			}
		}
	}
}
