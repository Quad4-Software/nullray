// SPDX-License-Identifier: 0BSD
package agent

import "core:os"
import "core:strings"
import "core:testing"
import "nullray:constants"
import "nullray:tools"

@(test)
test_verify_off_when_unset :: proc(t: ^testing.T) {
	os.unset_env(constants.ENV_VERIFY)
	_, off := verify_command_from_env(context.temp_allocator)
	testing.expect(t, off)
	cmd, disabled := resolve_verify_command("", context.temp_allocator)
	testing.expect(t, disabled)
	testing.expect_value(t, cmd, "")
}

@(test)
test_verify_on_uses_cascade :: proc(t: ^testing.T) {
	os.set_env(constants.ENV_VERIFY, "1")
	defer os.unset_env(constants.ENV_VERIFY)
	env_cmd, off := verify_command_from_env(context.temp_allocator)
	testing.expect(t, !off)
	testing.expect_value(t, env_cmd, "")
	cmd, disabled := resolve_verify_command("", context.temp_allocator)
	testing.expect(t, !disabled)
	testing.expect(t, len(cmd) > 0)
}

@(test)
test_verify_explicit_command :: proc(t: ^testing.T) {
	os.set_env(constants.ENV_VERIFY, "odin test nullray/ui")
	defer os.unset_env(constants.ENV_VERIFY)
	cmd, disabled := resolve_verify_command("ignored", context.temp_allocator)
	testing.expect(t, !disabled)
	testing.expect_value(t, cmd, "odin test nullray/ui")
}

@(test)
test_run_verify_nil_registry :: proc(t: ^testing.T) {
	ok, out := run_verify_command("make test", nil, context.temp_allocator)
	testing.expect(t, !ok)
	testing.expect(t, strings.contains(out, "no tools registry"))
}

@(test)
test_run_verify_missing_shell :: proc(t: ^testing.T) {
	reg: tools.Registry
	reg.tools = make([dynamic]tools.Tool)
	defer delete(reg.tools)
	ok, out := run_verify_command("make test", &reg, context.temp_allocator)
	testing.expect(t, !ok)
	testing.expect(t, strings.contains(out, "run_shell"))
}

@(test)
test_format_verify_nudge_prefix :: proc(t: ^testing.T) {
	msg := format_verify_nudge("make test", 1, 3, "boom", false, context.temp_allocator)
	testing.expect(t, strings.has_prefix(msg, VERIFY_USER_PREFIX))
	testing.expect(t, strings.contains(msg, "make test"))
	testing.expect(t, strings.contains(msg, "boom"))
}
