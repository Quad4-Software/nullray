// SPDX-License-Identifier: 0BSD
/*
search_tools deferred activation tests.
*/

package tools

import "core:strings"
import "core:testing"

@(test)
test_search_tools_activates_deferred :: proc(t: ^testing.T) {
	deferred_clear()
	tools_init()
	defer tools_destroy()

	out, err := tool_search_tools(`{"query":"audit_owasp"}`, context.allocator)
	defer delete(out)
	testing.expect_value(t, err, "")
	testing.expect(t, strings.contains(out, "audit_owasp"))
	testing.expect(t, deferred_active("audit_owasp"))

	lean_json := openai_tools_json(registry(), "edit", true, context.allocator)
	defer delete(lean_json)
	testing.expect(t, strings.contains(lean_json, "audit_owasp"))
}
