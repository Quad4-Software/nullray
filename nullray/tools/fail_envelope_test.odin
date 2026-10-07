// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package tools

import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"
import "nullray:constants"

@(private)
fd_fail_tool :: proc(args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	return "", strings.clone("read failed: ENOENT", allocator)
}

@(private)
fd_fail_registry :: proc() -> Registry {
	r: Registry
	r.tools = make([dynamic]Tool, context.temp_allocator)
	registry_register(&r, Tool{name = "fd_fail", kind = .Read, run = fd_fail_tool})
	registry_register(&r, Tool{name = "fd_write", kind = .Write, run = fd_fail_tool})
	return r
}

@(test)
test_error_envelope_shape :: proc(t: ^testing.T) {
	env := error_envelope("fake_tool", `{"path":"x"}`, "read failed: ENOENT", context.allocator)
	defer delete(env)
	testing.expect(t, strings.has_prefix(env, "error: "))
	testing.expect(t, strings.contains(env, "read failed"))
	testing.expect(t, strings.contains(env, "\nobserved: "))
	testing.expect(t, strings.contains(env, "\nalternatives: "))
}

@(test)
test_error_envelope_edit_old_string :: proc(t: ^testing.T) {
	env := error_envelope(
		"edit_file",
		`{"path":"a.odin","old_string":"zzz"}`,
		"old_string not found in a.odin: no match",
		context.allocator,
	)
	defer delete(env)
	testing.expect(t, strings.contains(env, "observed: no match for old_string in a.odin"))
	testing.expect(t, strings.contains(env, "grep_files"))
	testing.expect(t, strings.contains(env, "read_file"))
}

@(test)
test_error_envelope_run_shell_enoent :: proc(t: ^testing.T) {
	env := error_envelope("run_shell", `{"command":"fribblez --go"}`, "exec failed: ENOENT", context.allocator)
	defer delete(env)
	testing.expect(t, strings.contains(env, "observed: fribblez --go"))
	testing.expect(t, strings.contains(env, "list_dir"))
}

@(test)
test_error_envelope_missing_path_parent :: proc(t: ^testing.T) {
	root := "/tmp/nullray-fd-parent"
	_ = os.remove_all(root)
	testing.expect(t, os.make_directory_all(root) == nil)
	defer os.remove_all(root)
	missing := fmt.tprintf("%s/no/such/file.txt", root)
	env := error_envelope(
		"read_file",
		fmt.tprintf(`{{"path":%q}}`, missing),
		"read failed: ENOENT",
		context.allocator,
	)
	defer delete(env)
	testing.expect(t, strings.contains(env, missing))
	// Nearest existing parent dir is the seeded directory itself.
	testing.expect(t, strings.contains(env, fmt.tprintf("list_dir path=%s", root)))
	testing.expect(t, strings.contains(env, "glob_files"))
}

@(test)
test_arg_key_summary_shape :: proc(t: ^testing.T) {
	long_val := strings.repeat("ZQXWVYKJ", 16, context.temp_allocator)
	args := fmt.tprintf(`{{"path":"/x","n":3,"flag":true,"blob":%q}}`, long_val)
	s := arg_key_summary(args, context.allocator)
	defer delete(s)
	testing.expect(t, strings.contains(s, "path=/x"))
	testing.expect(t, strings.contains(s, "n=3"))
	testing.expect(t, strings.contains(s, "flag=true"))
	testing.expect(t, strings.contains(s, "blob=<128 bytes>"))
	// Long values summarize to a size marker, never the verbatim text.
	testing.expect(t, !strings.contains(s, "ZQXWVYKJ"))
	empty := arg_key_summary(`{"a":`, context.allocator)
	testing.expect_value(t, empty, "")
}

@(test)
test_describe_tool_failure_no_arg_echo :: proc(t: ^testing.T) {
	marker := strings.repeat("ZQXWVYKJ", 16, context.temp_allocator)
	args := fmt.tprintf(`{{"path":"/tmp/nope.txt","token":%q}}`, marker)
	err_env := "error: read failed: ENOENT\nobserved: /tmp/nope.txt\nalternatives: list_dir path=/tmp"
	d := describe_tool_failure("fake_tool", args, err_env, context.allocator)
	defer delete(d)
	testing.expect(t, strings.has_prefix(d, "tool fake_tool failed: read failed"))
	testing.expect(t, strings.contains(d, "path=/tmp/nope.txt"))
	testing.expect(t, strings.contains(d, "token=<128 bytes>"))
	testing.expect(t, !strings.contains(d, marker))
	testing.expect(t, !strings.contains(d, `"token"`))
	testing.expect(t, strings.contains(d, "observed: /tmp/nope.txt"))
	testing.expect(t, strings.contains(d, "alternatives: list_dir path=/tmp"))
}

@(test)
test_describe_tool_failure_plain_error :: proc(t: ^testing.T) {
	d := describe_tool_failure("x_tool", `{}`, "multi\nline\nerr", context.allocator)
	defer delete(d)
	testing.expect_value(t, d, "tool x_tool failed: multi line err")
}

@(test)
test_run_wraps_tool_errors :: proc(t: ^testing.T) {
	os.unset_env(constants.ENV_FAILURE_DESC)
	reg := fd_fail_registry()
	res, err := run(&reg, "fd_fail", `{"path":"x.txt"}`, "edit", context.allocator)
	defer delete(res)
	defer delete(err)
	testing.expect(t, strings.has_prefix(err, "error: read failed"))
	testing.expect(t, strings.contains(err, "\nobserved: "))
	testing.expect(t, strings.contains(err, "\nalternatives: "))
	// Mode and gate blocks get the envelope too.
	_, werr := run(&reg, "fd_write", `{}`, "ask", context.allocator)
	defer delete(werr)
	testing.expect(t, strings.has_prefix(werr, "error: tool blocked"))
	testing.expect(t, strings.contains(werr, "alternatives:"))
}

@(test)
test_run_fail_keeps_formation_errors :: proc(t: ^testing.T) {
	os.unset_env(constants.ENV_FAILURE_DESC)
	reg := fd_fail_registry()
	_, err := run(&reg, "fd_nope", `{}`, "edit", context.allocator)
	defer delete(err)
	testing.expect(t, strings.has_prefix(err, "unknown tool"))
	testing.expect(t, !strings.contains(err, "observed:"))
	testing.expect(t, err_is_call_formation("bad tool args JSON: x"))
	testing.expect(t, err_is_call_formation("unknown tool: foo"))
	testing.expect(t, err_is_call_formation("tool not runnable: foo"))
	testing.expect(t, err_is_call_formation("tool args must be a JSON object"))
	testing.expect(t, !err_is_call_formation("read failed: ENOENT"))
}

@(test)
test_run_fail_env_disable :: proc(t: ^testing.T) {
	os.set_env(constants.ENV_FAILURE_DESC, "0")
	defer os.unset_env(constants.ENV_FAILURE_DESC)
	testing.expect(t, !failure_desc_enabled())
	reg := fd_fail_registry()
	res, err := run(&reg, "fd_fail", `{"path":"x.txt"}`, "edit", context.allocator)
	defer delete(res)
	defer delete(err)
	testing.expect_value(t, err, "read failed: ENOENT")
}
