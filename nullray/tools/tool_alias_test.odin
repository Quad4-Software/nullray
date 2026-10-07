// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package tools

import "core:os"
import "core:strings"
import "core:testing"
import "nullray:constants"
import "nullray:provider"

@(private)
alias_test_table :: proc(entries: ..[2]string) -> map[string]string {
	m := make(map[string]string, context.temp_allocator)
	for e in entries {
		m[strings.clone(e[0], context.temp_allocator)] = strings.clone(e[1], context.temp_allocator)
	}
	return m
}

@(private)
save_rename_env :: proc() -> (saved: string, had: bool) {
	if v, ok := os.lookup_env(constants.ENV_TOOL_RENAME, context.temp_allocator); ok {
		return strings.clone(v, context.temp_allocator), true
	}
	return "", false
}

@(test)
test_tool_alias_emit_and_dispatch :: proc(t: ^testing.T) {
	tool_alias_reset_for_test()
	defer tool_alias_reset_for_test()
	reg: Registry
	registry_init(&reg)
	defer registry_destroy(&reg)

	tool_alias_install_for_test(alias_test_table({"read_file", "readFile"}))
	json := openai_tools_json(&reg, "edit", .Full, context.allocator)
	defer delete(json)
	testing.expect(t, strings.contains(json, `"name":"readFile"`))
	testing.expect(t, !strings.contains(json, `"name":"read_file"`))

	// describe_for_prompt shows the same alias so catalog and schema agree.
	cat := describe_for_prompt(&reg, context.allocator, "edit")
	defer delete(cat)
	testing.expect(t, strings.contains(cat, "readFile:"))

	// Dispatch resolves the alias back to the canonical tool.
	_, err := run(&reg, "readFile", `{"path":"/nonexistent-nullray-alias"}`, "edit", context.allocator)
	defer delete(err)
	testing.expect(t, !strings.contains(err, "unknown tool"))

	// Lookup seam resolves too.
	if tt, ok := registry_find(&reg, "readFile"); ok {
		testing.expect_value(t, tt.name, "read_file")
	} else {
		testing.expect(t, false, "alias lookup failed")
	}
	if _, ok := registry_find_exact(&reg, "readFile"); ok {
		testing.expect(t, false, "exact lookup should miss the alias")
	}
}

@(test)
test_tool_alias_validation :: proc(t: ^testing.T) {
	tool_alias_reset_for_test()
	defer tool_alias_reset_for_test()
	reg: Registry
	registry_init(&reg)
	defer registry_destroy(&reg)

	// Alias colliding with a real tool name is dropped.
	tool_alias_install_for_test(alias_test_table({"read_file", "write_file"}))
	tb := tool_alias_table(&reg, "", "m1", context.temp_allocator)
	testing.expect_value(t, len(tb), 0)

	// Malformed identifiers are dropped.
	tool_alias_install_for_test(alias_test_table({"read_file", "has space"}))
	tb = tool_alias_table(&reg, "", "m1", context.temp_allocator)
	testing.expect_value(t, len(tb), 0)
	tool_alias_install_for_test(alias_test_table({"read_file", "default_api.read_file"}))
	tb = tool_alias_table(&reg, "", "m1", context.temp_allocator)
	testing.expect_value(t, len(tb), 0)
	tool_alias_install_for_test(alias_test_table({"read_file", "9lives"}))
	tb = tool_alias_table(&reg, "", "m1", context.temp_allocator)
	testing.expect_value(t, len(tb), 0)

	// Unregistered canonicals are dropped, the mapping stays total.
	tool_alias_install_for_test(alias_test_table({"no_such_tool", "fine_name"}))
	tb = tool_alias_table(&reg, "", "m1", context.temp_allocator)
	testing.expect_value(t, len(tb), 0)

	// Duplicate aliases keep exactly one entry (map order picks which).
	tool_alias_install_for_test(alias_test_table({"read_file", "dup_alias"}, {"write_file", "dup_alias"}))
	tb = tool_alias_table(&reg, "", "m1", context.temp_allocator)
	testing.expect_value(t, len(tb), 1)
	kept := false
	for _, v in tb {
		kept = v == "dup_alias"
	}
	testing.expect(t, kept)

	// Valid entries pass through.
	tool_alias_install_for_test(alias_test_table({"read_file", "readFile"}, {"run_shell", "shell"}))
	tb = tool_alias_table(&reg, "", "m1", context.temp_allocator)
	testing.expect_value(t, len(tb), 2)
	testing.expect_value(t, tb["read_file"], "readFile")
	testing.expect_value(t, tb["run_shell"], "shell")
}

@(test)
test_tool_alias_env_disable :: proc(t: ^testing.T) {
	saved, had := save_rename_env()
	defer if had {
		os.set_env(constants.ENV_TOOL_RENAME, saved)
	} else {
		os.unset_env(constants.ENV_TOOL_RENAME)
	}
	os.set_env(constants.ENV_TOOL_RENAME, "0")
	tool_alias_reset_for_test()
	defer tool_alias_reset_for_test()
	reg: Registry
	registry_init(&reg)
	defer registry_destroy(&reg)

	tool_alias_install_for_test(alias_test_table({"read_file", "readFile"}))
	tb := tool_alias_table(&reg, "", "m1", context.temp_allocator)
	testing.expect_value(t, len(tb), 0)
	json := openai_tools_json(&reg, "edit", .Full, context.allocator)
	defer delete(json)
	testing.expect(t, strings.contains(json, `"name":"read_file"`))
	if _, ok := tool_alias_resolve("readFile"); ok {
		testing.expect(t, false, "resolve should stay off when disabled")
	}
}

@(test)
test_tool_alias_profile_lookup :: proc(t: ^testing.T) {
	tool_alias_reset_for_test()
	defer tool_alias_reset_for_test()
	defer provider.profile_reset_for_test()
	provider.profile_install_for_test(`{"profiles":[{"match":"qwen*","tool_names":{"read_file":"readFile"}}]}`)
	reg: Registry
	registry_init(&reg)
	defer registry_destroy(&reg)

	// Explicit model hits the glob, others do not.
	tb := tool_alias_table(&reg, "", "qwen2.5-coder", context.temp_allocator)
	testing.expect_value(t, len(tb), 1)
	testing.expect_value(t, tb["read_file"], "readFile")
	tb = tool_alias_table(&reg, "", "llama3", context.temp_allocator)
	testing.expect_value(t, len(tb), 0)

	// The last profile_for model fills in when the caller has no model.
	_, ok := provider.profile_for("qwen2.5-coder")
	testing.expect(t, ok)
	if v, okv := os.lookup_env(constants.ENV_MODEL, context.temp_allocator); okv && len(v) > 0 {
		return
	}
	tb = tool_alias_table(&reg, "", "", context.temp_allocator)
	testing.expect_value(t, len(tb), 1)
}
