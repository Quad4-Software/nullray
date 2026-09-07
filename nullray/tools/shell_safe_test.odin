// SPDX-License-Identifier: 0BSD
package tools

import "core:os"
import "core:testing"
import "nullray:constants"

@(test)
test_shell_deny_builtin_patterns :: proc(t: ^testing.T) {
	ok, reason := shell_command_allowed("rm -rf /")
	testing.expect(t, !ok)
	testing.expect(t, len(reason) > 0)
	delete(reason)

	ok2, reason2 := shell_command_allowed("echo hello")
	testing.expect(t, ok2)
	delete(reason2)
}

@(test)
test_shell_allow_list :: proc(t: ^testing.T) {
	os.set_env(constants.ENV_SHELL_ALLOW, "git ,ls")
	defer os.unset_env(constants.ENV_SHELL_ALLOW)

	ok, reason := shell_command_allowed("git status")
	testing.expect(t, ok)
	delete(reason)

	ok2, reason2 := shell_command_allowed("curl http://x")
	testing.expect(t, !ok2)
	testing.expect(t, len(reason2) > 0)
	delete(reason2)
}

@(test)
test_shell_confirm_without_autonomy :: proc(t: ^testing.T) {
	os.set_env(constants.ENV_PERMS, "allow")
	os.set_env(constants.ENV_SHELL_CONFIRM, "1")
	os.unset_env(constants.ENV_AUTONOMY)
	os.unset_env(constants.ENV_SHELL_AUTONOMY)
	defer os.unset_env(constants.ENV_SHELL_CONFIRM)
	defer os.unset_env(constants.ENV_PERMS)
	defer shell_deny_pending()

	ok, reason := shell_command_allowed("ls")
	testing.expect(t, !ok)
	testing.expect(t, len(reason) > 0)
	delete(reason)
}

@(test)
test_shell_empty_rejected :: proc(t: ^testing.T) {
	ok, reason := shell_command_allowed("   ")
	testing.expect(t, !ok)
	delete(reason)
}

@(test)
test_shell_blocks_cat_env :: proc(t: ^testing.T) {
	os.unset_env(constants.ENV_SECRETS_ALLOW)
	os.set_env(constants.ENV_PERMS, "yolo")
	defer os.unset_env(constants.ENV_PERMS)

	ok, reason := shell_command_allowed("cat .env")
	testing.expect(t, !ok)
	testing.expect(t, len(reason) > 0)
	delete(reason)
}
