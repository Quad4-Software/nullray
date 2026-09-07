// SPDX-License-Identifier: 0BSD
package tools

import "core:os"
import "core:testing"
import "nullray:constants"

@(test)
test_perms_from_string :: proc(t: ^testing.T) {
	p, ok := perms_from_string("yolo")
	testing.expect(t, ok)
	testing.expect(t, p == .Yolo)
	p2, ok2 := perms_from_string("ask")
	testing.expect(t, ok2)
	testing.expect(t, p2 == .Ask)
}

@(test)
test_shell_perms_ask_requires_allow :: proc(t: ^testing.T) {
	os.set_env(constants.ENV_PERMS, "ask")
	os.unset_env(constants.ENV_SHELL_ALLOW)
	defer os.unset_env(constants.ENV_PERMS)
	defer shell_deny_pending()

	ok, reason := shell_command_allowed("ls")
	testing.expect(t, !ok)
	testing.expect(t, len(reason) > 0)
	delete(reason)

	os.set_env(constants.ENV_SHELL_ALLOW, "ls")
	defer os.unset_env(constants.ENV_SHELL_ALLOW)
	ok2, reason2 := shell_command_allowed("ls -la")
	testing.expect(t, ok2)
	delete(reason2)
}

@(test)
test_shell_perms_yolo_skips_allow :: proc(t: ^testing.T) {
	os.set_env(constants.ENV_PERMS, "yolo")
	os.set_env(constants.ENV_SHELL_ALLOW, "git")
	defer os.unset_env(constants.ENV_PERMS)
	defer os.unset_env(constants.ENV_SHELL_ALLOW)

	ok, reason := shell_command_allowed("echo hi")
	testing.expect(t, ok)
	delete(reason)
}
