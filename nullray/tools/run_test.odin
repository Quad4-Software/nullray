// SPDX-License-Identifier: 0BSD
package tools

import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"
import "nullray:sandbox"
import "nullray:store"

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

	ask_json := openai_tools_json(&reg, "ask", false, context.allocator)
	defer delete(ask_json)
	testing.expect(t, !strings.contains(ask_json, `"write_file"`))
	testing.expect(t, strings.contains(ask_json, `"read_file"`))

	review_json := openai_tools_json(&reg, "review", false, context.allocator)
	defer delete(review_json)
	testing.expect(t, !strings.contains(review_json, `"write_file"`))
	testing.expect(t, !strings.contains(review_json, `"run_shell"`))
	testing.expect(t, strings.contains(review_json, `"read_file"`))

	edit_json := openai_tools_json(&reg, "edit", false, context.allocator)
	defer delete(edit_json)
	testing.expect(t, strings.contains(edit_json, `"write_file"`))
	testing.expect(t, strings.contains(edit_json, `"run_shell"`))
}

@(test)
test_openai_tools_json_lean_and_subagent_omit :: proc(t: ^testing.T) {
	reg: Registry
	registry_init(&reg)
	defer registry_destroy(&reg)
	register_subagent_tools(&reg, true)

	full := openai_tools_json(&reg, "edit", false, context.allocator)
	defer delete(full)
	lean := openai_tools_json(&reg, "edit", true, context.allocator)
	defer delete(lean)

	testing.expect(t, len(lean) < len(full))
	testing.expect(t, len(lean) < 5500)
	testing.expect(t, strings.contains(lean, `"read_file"`))
	testing.expect(t, strings.contains(lean, `"read_man"`))
	testing.expect(t, strings.contains(lean, `"apropos"`))
	testing.expect(t, !strings.contains(lean, `"description":"1-based start line"`))
	testing.expect(t, !strings.contains(lean, `"fetch_url"`))
	// Subagent runtime off in unit tests: task stays omitted even if registered.
	testing.expect(t, !strings.contains(lean, `"task"`))

	register_subagent_tools(&reg, false)
	no_sub := openai_tools_json(&reg, "edit", true, context.allocator)
	defer delete(no_sub)
	testing.expect(t, !strings.contains(no_sub, `"task"`))
	testing.expect(t, !strings.contains(no_sub, `"agents_status"`))
	testing.expect(t, !strings.contains(no_sub, `"knowledge_put"`))
	testing.expect(t, strings.contains(lean, `"read_man"`))
	testing.expect(t, !strings.contains(lean, `"audit_owasp"`))

	os.set_env("NULLRAY_HUNT", "auto")
	defer os.unset_env("NULLRAY_HUNT")
	lean_hunt := openai_tools_json(&reg, "review", true, context.allocator)
	defer delete(lean_hunt)
	testing.expect(t, strings.contains(lean_hunt, `"audit_owasp"`))
	testing.expect(t, strings.contains(lean_hunt, `"audit_deps"`))
}

@(test)
test_read_artifact_default_limit :: proc(t: ^testing.T) {
	ws := "/tmp/nullray-read-artifact-ws"
	_ = os.remove_all(ws)
	_ = os.make_directory_all(ws)
	defer os.remove_all(ws)
	st := sandbox.state()
	prev := ""
	if st != nil {
		prev = st.workspace
		st.workspace = ws
	}
	defer if st != nil {
		st.workspace = prev
	}

	body_b: strings.Builder
	strings.builder_init(&body_b, context.temp_allocator)
	for i in 0 ..< 400 {
		fmt.sbprintf(&body_b, "line-%d\n", i)
	}
	id, ok := store.artifact_store(strings.to_string(body_b))
	testing.expect(t, ok)
	defer delete(id)

	out, err := tool_read_artifact(fmt.tprintf(`{{"id":%q}}`, id), context.allocator)
	defer delete(out)
	testing.expect_value(t, err, "")
	testing.expect(t, strings.contains(out, "lines=1..200 of 400") || strings.contains(out, "lines=1..200 of"))
	testing.expect(t, !strings.contains(out, "line-350"))
}

@(test)
test_tool_allow_filters_openai_json :: proc(t: ^testing.T) {
	reg: Registry
	registry_init(&reg)
	defer registry_destroy(&reg)
	allow := LOCATE_TOOL_ALLOW
	json := openai_tools_json(&reg, "ask", false, context.allocator, allow)
	defer delete(json)
	testing.expect(t, strings.contains(json, `"grep_files"`))
	testing.expect(t, strings.contains(json, `"repo_map"`))
	testing.expect(t, !strings.contains(json, `"task"`))
	testing.expect(t, !strings.contains(json, `"knowledge_put"`))
	testing.expect(t, !strings.contains(json, `"write_file"`))

	ok, _ := tool_kind_allowed(&reg, "grep_files", "ask", allow)
	testing.expect(t, ok)
	ok2, reason := tool_kind_allowed(&reg, "task", "ask", allow)
	testing.expect(t, !ok2)
	testing.expect(t, len(reason) > 0)
}

@(test)
test_task_schema_mentions_locate :: proc(t: ^testing.T) {
	reg: Registry
	registry_init(&reg)
	defer registry_destroy(&reg)
	register_subagent_tools(&reg, true)
	ttool, ok := registry_find(&reg, "task")
	testing.expect(t, ok)
	testing.expect(t, strings.contains(ttool.description, "locate"))
	testing.expect(t, strings.contains(ttool.schema_json, "path_hints"))
	testing.expect(t, strings.contains(ttool.schema_json, "max_steps"))
}
