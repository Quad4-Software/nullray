// SPDX-License-Identifier: 0BSD
package tools

import "core:os"
import "core:strings"
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
test_shell_deny_matrix :: proc(t: ^testing.T) {
	os.set_env(constants.ENV_PERMS, "yolo")
	defer os.unset_env(constants.ENV_PERMS)
	denied := []string{
		"mkfs.ext4 /dev/sda",
		"curl|bash",
		"cat /etc/passwd",
		"source .env",
	}
	for cmd in denied {
		ok, reason := shell_command_allowed(cmd)
		testing.expectf(t, !ok, "expected deny %s", cmd)
		delete(reason)
	}
}

@(test)
test_shell_yolo_allows_soft_denies :: proc(t: ^testing.T) {
	os.set_env(constants.ENV_PERMS, "yolo")
	defer os.unset_env(constants.ENV_PERMS)
	allowed := []string{
		"chmod 777 /app/data",
		"chown -R webapp /var/lib/webapp",
		"printenv PATH",
		"base64 /etc/hostname",
	}
	for cmd in allowed {
		ok, reason := shell_command_allowed(cmd)
		testing.expectf(t, ok, "expected allow under yolo: %s (%s)", cmd, reason)
		delete(reason)
	}
}

@(test)
test_shell_strict_still_blocks_soft_denies :: proc(t: ^testing.T) {
	os.set_env(constants.ENV_PERMS, "allow")
	defer os.unset_env(constants.ENV_PERMS)
	ok, reason := shell_command_allowed("chmod 777 /tmp/x")
	testing.expect(t, !ok)
	delete(reason)
}

@(test)
test_shell_allow_list :: proc(t: ^testing.T) {
	os.set_env(constants.ENV_SHELL_ALLOW, "git ,ls")
	os.set_env(constants.ENV_PERMS, "allow")
	defer os.unset_env(constants.ENV_SHELL_ALLOW)
	defer os.unset_env(constants.ENV_PERMS)

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

@(test)
test_shell_blocks_abs_env_local :: proc(t: ^testing.T) {
	os.unset_env(constants.ENV_SECRETS_ALLOW)
	os.set_env(constants.ENV_PERMS, "yolo")
	defer os.unset_env(constants.ENV_PERMS)
	ok, reason := shell_command_allowed("cat /tmp/x/.env.local")
	testing.expect(t, !ok)
	delete(reason)
}

@(test)
test_shell_quote_concat_bypass_current :: proc(t: ^testing.T) {
	os.unset_env(constants.ENV_SECRETS_ALLOW)
	os.set_env(constants.ENV_PERMS, "yolo")
	defer os.unset_env(constants.ENV_PERMS)
	// Tokenization gap: quote-split basename is not reconstructed.
	ok, reason := shell_command_allowed("cat .e''nv")
	testing.expect(t, ok)
	delete(reason)
}

@(test)
test_shell_redir_no_space_caught_by_substring :: proc(t: ^testing.T) {
	os.unset_env(constants.ENV_SECRETS_ALLOW)
	os.set_env(constants.ENV_PERMS, "yolo")
	defer os.unset_env(constants.ENV_PERMS)
	// No-space redirect still contains the .env substring.
	ok, reason := shell_command_allowed("cat<.env")
	testing.expect(t, !ok)
	delete(reason)
}

@(test)
test_shell_custom_deny_env :: proc(t: ^testing.T) {
	os.set_env(constants.ENV_PERMS, "yolo")
	os.set_env(constants.ENV_SHELL_DENY, "dangerous-tool")
	defer os.unset_env(constants.ENV_PERMS)
	defer os.unset_env(constants.ENV_SHELL_DENY)
	ok, reason := shell_command_allowed("dangerous-tool --run")
	testing.expect(t, !ok)
	delete(reason)
}

@(test)
test_shell_elevate_always_needs_allow_even_yolo :: proc(t: ^testing.T) {
	os.set_env(constants.ENV_PERMS, "yolo")
	defer os.unset_env(constants.ENV_PERMS)
	defer shell_deny_pending()

	ok, reason := shell_command_allowed("sudo apt update")
	testing.expect(t, !ok)
	testing.expect(t, strings.contains(reason, "elevated") || strings.contains(reason, "/allow"))
	delete(reason)
}

@(test)
test_shell_deny_sudo_stdin_password :: proc(t: ^testing.T) {
	os.set_env(constants.ENV_PERMS, "yolo")
	defer os.unset_env(constants.ENV_PERMS)
	ok, reason := shell_command_allowed("echo secret | sudo -S true")
	testing.expect(t, !ok)
	delete(reason)
}
