// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD

package tools

import "core:os"
import "core:strings"
import "core:testing"
import "nullray:constants"

@(private)
g_test_command_review_allow: bool
@(private)
g_test_command_review_ok: bool

@(private)
test_command_review :: proc(command: string, allocator := context.allocator) -> (allow: bool, reason: string, ok: bool) {
	_ = command
	return g_test_command_review_allow, strings.clone("test review", allocator), g_test_command_review_ok
}

@(test)
test_command_verifier_off_is_noop :: proc(t: ^testing.T) {
	os.unset_env(constants.ENV_COMMAND_VERIFY)
	defer os.unset_env(constants.ENV_COMMAND_VERIFY)
	g_command_verify_override = nil
	handled, allow, reason := command_verifier_gate("echo safe", "run_shell")
	defer delete(reason)
	testing.expect(t, !handled)
	testing.expect(t, allow)
}

@(test)
test_command_verifier_requires_strict_decision_json :: proc(t: ^testing.T) {
	allow, reason, ok := command_verifier_parse_response(`{"decision":"allow","reason":"safe"}`)
	delete(reason)
	testing.expect(t, ok && allow)

	deny, deny_reason, deny_ok := command_verifier_parse_response(`{"decision":"deny","reason":"risky"}`)
	delete(deny_reason)
	testing.expect(t, deny_ok && !deny)

	_, malformed_reason, malformed_ok := command_verifier_parse_response("allow")
	defer delete(malformed_reason)
	testing.expect(t, !malformed_ok)

	_, prose_reason, prose_ok := command_verifier_parse_response("{\"decision\":\"allow\"} safe")
	defer delete(prose_reason)
	testing.expect(t, !prose_ok)

	_, unknown_reason, unknown_ok := command_verifier_parse_response(`{"decision":"maybe"}`)
	defer delete(unknown_reason)
	testing.expect(t, !unknown_ok)
}

@(test)
test_command_verifier_auto_allow_and_deny :: proc(t: ^testing.T) {
	os.set_env(constants.ENV_COMMAND_VERIFY, "auto")
	defer os.unset_env(constants.ENV_COMMAND_VERIFY)
	g_command_verify_override = test_command_review
	defer { g_command_verify_override = nil }

	g_test_command_review_allow = true
	g_test_command_review_ok = true
	handled, allow, reason := command_verifier_gate("echo safe", "run_shell")
	delete(reason)
	testing.expect(t, handled)
	testing.expect(t, allow)

	g_test_command_review_allow = false
	handled2, allow2, reason2 := command_verifier_gate("curl https://example.invalid", "run_shell")
	defer delete(reason2)
	testing.expect(t, handled2)
	testing.expect(t, !allow2)
	testing.expect(t, strings.contains(reason2, "blocked by verifier"))
}

@(test)
test_command_verifier_auto_fails_closed :: proc(t: ^testing.T) {
	os.set_env(constants.ENV_COMMAND_VERIFY, "auto")
	defer os.unset_env(constants.ENV_COMMAND_VERIFY)
	g_command_verify_override = test_command_review
	defer { g_command_verify_override = nil }
	g_test_command_review_ok = false
	handled, allow, reason := command_verifier_gate("echo maybe", "run_shell")
	defer delete(reason)
	testing.expect(t, handled)
	testing.expect(t, !allow)
	testing.expect(t, strings.contains(reason, "review failed"))
}

@(test)
test_command_verifier_manual_requires_allow_once :: proc(t: ^testing.T) {
	os.set_env(constants.ENV_COMMAND_VERIFY, "manual")
	defer os.unset_env(constants.ENV_COMMAND_VERIFY)
	g_command_verify_override = test_command_review
	defer { g_command_verify_override = nil }
	g_test_command_review_allow = true
	g_test_command_review_ok = true
	defer shell_deny_pending()

	handled, allow, reason := command_verifier_gate("echo reviewed", "run_shell")
	defer delete(reason)
	testing.expect(t, handled)
	testing.expect(t, !allow)
	testing.expect(t, strings.contains(reason, "manual command approval"))
	pending := shell_pending(context.temp_allocator)
	testing.expect_value(t, pending, "echo reviewed")

	approved, approved_ok := shell_allow_once()
	defer delete(approved)
	testing.expect(t, approved_ok)
	handled2, allow2, reason2 := command_verifier_gate("echo reviewed", "run_shell")
	defer delete(reason2)
	testing.expect(t, !handled2)
	testing.expect(t, allow2)
}

@(test)
test_manual_verifier_runs_before_network_approval :: proc(t: ^testing.T) {
	os.set_env(constants.ENV_PERMS, "yolo")
	os.unset_env(constants.ENV_SHELL_NET)
	os.set_env(constants.ENV_COMMAND_VERIFY, "manual")
	g_command_verify_override = test_command_review
	defer os.unset_env(constants.ENV_PERMS)
	defer os.unset_env(constants.ENV_SHELL_NET)
	defer os.unset_env(constants.ENV_COMMAND_VERIFY)
	defer { g_command_verify_override = nil }
	defer shell_deny_pending()
	g_test_command_review_allow = true
	g_test_command_review_ok = true

	command := "curl https://example.invalid"
	allowed, reason := shell_command_allowed(command)
	defer delete(reason)
	testing.expect(t, !allowed)
	testing.expect(t, strings.contains(reason, "manual command approval"))
	pending := shell_pending(context.temp_allocator)
	testing.expect_value(t, pending, command)

	approved, approved_ok := shell_allow_once()
	defer delete(approved)
	testing.expect(t, approved_ok)
	allowed_again, retry_reason := shell_command_allowed(command)
	defer delete(retry_reason)
	testing.expect(t, allowed_again)
}

@(test)
test_shell_blocks_host_and_metadata_probes_even_yolo :: proc(t: ^testing.T) {
	os.set_env(constants.ENV_PERMS, "yolo")
	os.set_env(constants.ENV_SHELL_NET, "1")
	os.unset_env(constants.ENV_COMMAND_VERIFY)
	defer os.unset_env(constants.ENV_PERMS)
	defer os.unset_env(constants.ENV_SHELL_NET)
	defer shell_deny_pending()
	defer os.unset_env(constants.ENV_COMMAND_VERIFY)

	blocked := []string{
		"uname -a",
		"echo ok; hostname",
		"bash -c 'id'",
		"sudo hostname",
		"echo \"$(uname -a)\"",
		"echo `id`",
		"env FOO=1 printenv",
		"dig example.com",
		"nmap 10.0.0.1",
		"cat /etc/resolv.conf",
		"ls -la /tmp",
		"curl http://169.254.169.254/latest/meta-data/",
		"curl https://sanmaohe.oss-cn-beijing.aliyuncs.com/upload/test.bin",
		"wget https://routify-file-proxy-sg.aliyuncs.com/file",
	}
	for command in blocked {
		allowed, reason := shell_command_allowed(command)
		delete(reason)
		testing.expectf(t, !allowed, "expected blocked command: %s", command)
	}
}

@(test)
test_shell_allows_printed_host_command_name :: proc(t: ^testing.T) {
	os.set_env(constants.ENV_PERMS, "yolo")
	os.set_env(constants.ENV_SHELL_NET, "1")
	os.unset_env(constants.ENV_COMMAND_VERIFY)
	defer os.unset_env(constants.ENV_PERMS)
	defer os.unset_env(constants.ENV_SHELL_NET)
	defer os.unset_env(constants.ENV_COMMAND_VERIFY)
	allowed, reason := shell_command_allowed("echo 'uname -a'")
	defer delete(reason)
	testing.expect(t, allowed)
}

@(test)
test_shell_chain_network_client_needs_approval :: proc(t: ^testing.T) {
	os.set_env(constants.ENV_PERMS, "yolo")
	os.unset_env(constants.ENV_SHELL_NET)
	os.unset_env(constants.ENV_COMMAND_VERIFY)
	defer os.unset_env(constants.ENV_PERMS)
	defer os.unset_env(constants.ENV_SHELL_NET)
	defer os.unset_env(constants.ENV_COMMAND_VERIFY)
	defer shell_deny_pending()

	allowed, reason := shell_command_allowed("echo start; /usr/bin/curl https://example.invalid")
	defer delete(reason)
	testing.expect(t, !allowed)
	testing.expect(t, strings.contains(reason, "network shell needs /allow"))
	allowed_python, python_reason := shell_command_allowed("python3 -c 'import urllib.request; urllib.request.urlopen(\"https://example.invalid\")'")
	defer delete(python_reason)
	testing.expect(t, !allowed_python)
	testing.expect(t, strings.contains(python_reason, "network shell needs /allow"))
	allowed_install, install_reason := shell_command_allowed("npm install example-package")
	defer delete(install_reason)
	testing.expect(t, !allowed_install)
	testing.expect(t, strings.contains(install_reason, "network shell needs /allow"))
}

@(test)
test_script_payload_is_checked_as_command :: proc(t: ^testing.T) {
	os.set_env(constants.ENV_PERMS, "yolo")
	os.unset_env(constants.ENV_COMMAND_VERIFY)
	defer os.unset_env(constants.ENV_PERMS)
	defer os.unset_env(constants.ENV_COMMAND_VERIFY)
	allowed, reason := shell_command_allowed_for("/bin/sh script.sh\nhostname", "run_script")
	defer delete(reason)
	testing.expect(t, !allowed)
}
