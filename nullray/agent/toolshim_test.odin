// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Toolshim env gating, heuristic, and output parse tests.
*/

package agent

import "core:os"
import "core:strings"
import "core:testing"
import "nullray:constants"
import "nullray:provider"
import "nullray:tools"

@(private)
shim_test_registry :: proc() -> tools.Registry {
	r: tools.Registry
	r.tools = make([dynamic]tools.Tool, context.temp_allocator)
	tools.registry_register(&r, tools.Tool{name = "read_file", kind = .Read})
	tools.registry_register(&r, tools.Tool{name = "run_shell", kind = .Shell})
	tools.registry_register(&r, tools.Tool{name = "write_file", kind = .Write})
	return r
}

@(test)
test_toolshim_env_gating :: proc(t: ^testing.T) {
	os.unset_env(constants.ENV_TOOLSHIM)
	_, on := toolshim_model("main-model")
	testing.expect(t, !on)

	os.set_env(constants.ENV_TOOLSHIM, "0")
	m, on0 := toolshim_model("main-model")
	testing.expect(t, !on0)
	os.set_env(constants.ENV_TOOLSHIM, "off")
	_, on_off := toolshim_model("main-model")
	testing.expect(t, !on_off)

	os.set_env(constants.ENV_TOOLSHIM, "1")
	defer os.unset_env(constants.ENV_TOOLSHIM)
	m1, on1 := toolshim_model("main-model")
	testing.expect(t, on1)
	testing.expect_value(t, m1, "main-model")

	os.set_env(constants.ENV_TOOLSHIM, "on")
	m2, on2 := toolshim_model("main-model")
	testing.expect(t, on2)
	testing.expect_value(t, m2, "main-model")

	os.set_env(constants.ENV_TOOLSHIM, "qwen2.5-coder:7b")
	m3, on3 := toolshim_model("main-model")
	testing.expect(t, on3)
	testing.expect_value(t, m3, "qwen2.5-coder:7b")
}

@(test)
test_shim_heuristic :: proc(t: ^testing.T) {
	reg := shim_test_registry()
	// A JSON-ish call object looks toolish.
	testing.expect(t, shim_text_looks_toolish(`{"name": "read_file", "arguments": {"path": "x"}}`, &reg))
	testing.expect(t, shim_text_looks_toolish(`I will call {"function": "run_shell"} now`, &reg))
	// A registered tool name alone counts too.
	testing.expect(t, shim_text_looks_toolish("Let me use write_file for this.", &reg))
	// Plain prose does not.
	testing.expect(t, !shim_text_looks_toolish("The task is done, nothing left.", &reg))
	testing.expect(t, !shim_text_looks_toolish("", &reg))
	testing.expect(t, !shim_text_looks_toolish("{}", &reg))
}

@(test)
test_toolshim_parse_call_basic :: proc(t: ^testing.T) {
	reg := shim_test_registry()
	call, ok := toolshim_parse_call(`{"name":"read_file","arguments":{"path":"a.txt"}}`, &reg, 1)
	testing.expect(t, ok)
	testing.expect_value(t, call.name, "read_file")
	testing.expect_value(t, call.id, "shim-1")
	testing.expect(t, strings.contains(call.arguments, `"a.txt"`))
	provider_destroy_test_call(&call)
}

@(test)
test_toolshim_parse_call_openai_shape :: proc(t: ^testing.T) {
	reg := shim_test_registry()
	call, ok := toolshim_parse_call(
		`{"function":{"name":"run_shell","arguments":{"cmd":"ls"}}}`,
		&reg,
		2,
	)
	testing.expect(t, ok)
	testing.expect_value(t, call.name, "run_shell")
	testing.expect(t, strings.contains(call.arguments, `"ls"`))
	provider_destroy_test_call(&call)
}

@(test)
test_toolshim_parse_call_fenced_and_noisy :: proc(t: ^testing.T) {
	reg := shim_test_registry()
	text := "Sure, here you go:\n```json\n{\"name\":\"read_file\",\"arguments\":{\"path\":\"b.md\"}}\n```\nDone."
	call, ok := toolshim_parse_call(text, &reg, 3)
	testing.expect(t, ok)
	testing.expect_value(t, call.name, "read_file")
	provider_destroy_test_call(&call)
}

@(test)
test_toolshim_parse_call_rejects_unknown_and_junk :: proc(t: ^testing.T) {
	reg := shim_test_registry()
	_, ok := toolshim_parse_call(`{"name":"delete_everything","arguments":{}}`, &reg, 1)
	testing.expect(t, !ok)
	_, ok2 := toolshim_parse_call("no json here", &reg, 1)
	testing.expect(t, !ok2)
	_, ok3 := toolshim_parse_call(`{"arguments":{"x":1}}`, &reg, 1)
	testing.expect(t, !ok3)
	_, ok4 := toolshim_parse_call(`{"name":"read_file","arguments":"{bad json"`, &reg, 1)
	testing.expect(t, !ok4)
}

@(test)
test_toolshim_parse_call_first_object_wins :: proc(t: ^testing.T) {
	reg := shim_test_registry()
	// Two JSON objects: the first balanced one is the call, the trailing
	// object must not smear the slice across both.
	text := `{"name":"read_file","arguments":{"path":"a"}} then {"name":"write_file"}`
	call, ok := toolshim_parse_call(text, &reg, 1)
	testing.expect(t, ok)
	testing.expect_value(t, call.name, "read_file")
	provider_destroy_test_call(&call)

	// Trailing prose with a stray brace must not break extraction.
	text2 := `{"name":"run_shell","arguments":{"cmd":"ls"}} } trailing`
	call2, ok2 := toolshim_parse_call(text2, &reg, 2)
	testing.expect(t, ok2)
	testing.expect_value(t, call2.name, "run_shell")
	provider_destroy_test_call(&call2)

	// Braces inside string values do not close the object early.
	text3 := `{"name":"read_file","arguments":{"path":"a{b}.txt"}}`
	call3, ok3 := toolshim_parse_call(text3, &reg, 3)
	testing.expect(t, ok3)
	testing.expect(t, strings.contains(call3.arguments, "a{b}.txt"))
	provider_destroy_test_call(&call3)
}

@(test)
test_toolshim_parse_call_normalizes_name :: proc(t: ^testing.T) {
	reg := shim_test_registry()
	call, ok := toolshim_parse_call(`{"name":"read-file","arguments":{"path":"a"}}`, &reg, 1)
	testing.expect(t, ok)
	testing.expect_value(t, call.name, "read_file")
	provider_destroy_test_call(&call)
}

@(test)
test_toolshim_tool_list_gates_modes :: proc(t: ^testing.T) {
	reg := shim_test_registry()
	edit_list := toolshim_tool_list(&reg, "edit", nil, context.temp_allocator)
	testing.expect(t, strings.contains(edit_list, "read_file (read)"))
	testing.expect(t, strings.contains(edit_list, "run_shell (shell)"))
	ask_list := toolshim_tool_list(&reg, "ask", nil, context.temp_allocator)
	testing.expect(t, strings.contains(ask_list, "read_file"))
	testing.expect(t, !strings.contains(ask_list, "run_shell"))
	testing.expect(t, !strings.contains(ask_list, "write_file"))
}

@(private)
provider_destroy_test_call :: proc(c: ^provider.Tool_Call) {
	delete(c.id)
	delete(c.name)
	delete(c.arguments)
}
