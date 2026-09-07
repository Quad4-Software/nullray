// SPDX-License-Identifier: 0BSD
package tools

import "core:strings"
import "core:testing"

@(test)
test_tool_kind_gating_ask_blocks_write :: proc(t: ^testing.T) {
	reg: Registry
	registry_init(&reg)
	defer registry_destroy(&reg)

	ok, reason := tool_kind_allowed(&reg, "write_file", "ask")
	testing.expect(t, !ok)
	testing.expect(t, len(reason) > 0)

	ok2, _ := tool_kind_allowed(&reg, "read_file", "ask")
	testing.expect(t, ok2)

	ok3, reason3 := tool_kind_allowed(&reg, "run_shell", "plan")
	testing.expect(t, !ok3)
	testing.expect(t, len(reason3) > 0)

	ok4, _ := tool_kind_allowed(&reg, "write_file", "edit")
	testing.expect(t, ok4)

	ok5, reason5 := tool_kind_allowed(&reg, "mcp:demo:x", "ask")
	testing.expect(t, !ok5)
	testing.expect(t, len(reason5) > 0)

	ok6, reason6 := tool_kind_allowed(&reg, "write_file", "review")
	testing.expect(t, !ok6)
	testing.expect(t, len(reason6) > 0)

	ok7, _ := tool_kind_allowed(&reg, "read_file", "review")
	testing.expect(t, ok7)
}

@(test)
test_openai_tools_json_filters_by_mode :: proc(t: ^testing.T) {
	reg: Registry
	registry_init(&reg)
	defer registry_destroy(&reg)

	ask_json := openai_tools_json(&reg, "ask", context.allocator)
	defer delete(ask_json)
	testing.expect(t, !strings.contains(ask_json, `"write_file"`))
	testing.expect(t, strings.contains(ask_json, `"read_file"`))

	review_json := openai_tools_json(&reg, "review", context.allocator)
	defer delete(review_json)
	testing.expect(t, !strings.contains(review_json, `"write_file"`))
	testing.expect(t, !strings.contains(review_json, `"run_shell"`))
	testing.expect(t, strings.contains(review_json, `"read_file"`))

	edit_json := openai_tools_json(&reg, "edit", context.allocator)
	defer delete(edit_json)
	testing.expect(t, strings.contains(edit_json, `"write_file"`))
	testing.expect(t, strings.contains(edit_json, `"run_shell"`))
}
