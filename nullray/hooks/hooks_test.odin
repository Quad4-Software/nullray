// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package hooks

import "core:strings"
import "core:testing"

@(test)
test_event_names_match_config_keys :: proc(t: ^testing.T) {
	testing.expect_value(t, event_name(.PreToolUse), "PreToolUse")
	testing.expect_value(t, event_name(.PostToolUse), "PostToolUse")
	testing.expect_value(t, event_name(.SessionStart), "SessionStart")
	testing.expect_value(t, event_name(.SessionEnd), "SessionEnd")
	testing.expect_value(t, event_name(.Stop), "Stop")
	testing.expect_value(t, event_name(.PreCommit), "PreCommit")
	testing.expect_value(t, event_name(.UserPromptSubmit), "UserPromptSubmit")
	testing.expect_value(t, event_name(.PermissionRequest), "PermissionRequest")
	testing.expect_value(t, event_name(.PermissionDenied), "PermissionDenied")
	testing.expect_value(t, event_name(.SubagentStart), "SubagentStart")
	testing.expect_value(t, event_name(.SubagentStop), "SubagentStop")
	testing.expect_value(t, event_name(.Notification), "Notification")
}

@(test)
test_commands_for_new_events :: proc(t: ^testing.T) {
	cfg := Hook_File{
		user_prompt_submit = {"prompt.sh"},
		permission_request = {"perm.sh"},
		permission_denied  = {"denied.sh"},
		subagent_start     = {"substart.sh"},
		subagent_stop      = {"substop.sh"},
		notification       = {"notify.sh"},
	}
	testing.expect_value(t, len(commands_for(&cfg, .UserPromptSubmit)), 1)
	testing.expect_value(t, len(commands_for(&cfg, .PermissionRequest)), 1)
	testing.expect_value(t, len(commands_for(&cfg, .PermissionDenied)), 1)
	testing.expect_value(t, len(commands_for(&cfg, .SubagentStart)), 1)
	testing.expect_value(t, len(commands_for(&cfg, .SubagentStop)), 1)
	testing.expect_value(t, len(commands_for(&cfg, .Notification)), 1)
	testing.expect_value(t, commands_for(&cfg, .UserPromptSubmit)[0], "prompt.sh")
}

@(test)
test_run_command_closes_stdin_eof :: proc(t: ^testing.T) {
	// Commands reading stdin to EOF must finish inside the timeout; the
	// writer thread closes the pipe write end after delivering the input.
	code, timed, _, _ := run_command("grep -q marker_xyz", `{"a":"marker_xyz"}`)
	testing.expectf(t, !timed && code == 0, "grep match: code=%d timed=%v", code, timed)

	code2, timed2, _, _ := run_command("grep -q marker_xyz", `{"a":"other"}`)
	testing.expectf(t, !timed2 && code2 == 1, "grep miss: code=%d timed=%v", code2, timed2)

	code3, timed3, _, _ := run_command("cat > /dev/null", `{"big":"payload"}`)
	testing.expectf(t, !timed3 && code3 == 0, "cat eof: code=%d timed=%v", code3, timed3)
}

@(test)
test_run_command_exit2_blocks :: proc(t: ^testing.T) {
	code, timed, _, _ := run_command("exit 2", "")
	testing.expectf(t, code == 2 && !timed, "code=%d timed=%v", code, timed)
}

@(test)
test_run_command_captures_stdout :: proc(t: ^testing.T) {
	code, timed, out, _ := run_command("printf 'hello-hook'", "")
	testing.expectf(t, code == 0 && !timed, "code=%d timed=%v", code, timed)
	testing.expect_value(t, out, "hello-hook")
}

@(test)
test_apply_hook_output_permission_decisions :: proc(t: ^testing.T) {
	res: Result
	apply_hook_output(.PermissionRequest, "noise\n{\"decision\":\"allow\"}", &res)
	testing.expect_value(t, res.decision, "allow")
	result_destroy(&res)

	res2: Result
	apply_hook_output(.PermissionRequest, `{"decision":"deny","reason":"nope"}`, &res2)
	testing.expect_value(t, res2.decision, "deny")
	testing.expect_value(t, res2.reason, "nope")
	result_destroy(&res2)

	// Decision lines are ignored for events that cannot answer.
	res3: Result
	apply_hook_output(.SessionStart, `{"decision":"allow"}`, &res3)
	testing.expect_value(t, res3.decision, "")
}

@(test)
test_apply_hook_output_pretooluse_rewrite :: proc(t: ^testing.T) {
	res: Result
	apply_hook_output(.PreToolUse, `{"rewrite":{"path":"a.txt","content":"x"}}`, &res)
	testing.expectf(t, len(res.rewrite_args) > 0, "rewrite_args empty")
	testing.expect(t, strings.contains(res.rewrite_args, `"a.txt"`))
	result_destroy(&res)

	res2: Result
	apply_hook_output(.PreToolUse, `{"decision":"rewrite","args":{"command":"ls"}}`, &res2)
	testing.expectf(t, len(res2.rewrite_args) > 0, "rewrite_args empty")
	testing.expect(t, strings.contains(res2.rewrite_args, `"ls"`))
	result_destroy(&res2)

	// Rewrite keys must not fire on other events.
	res3: Result
	apply_hook_output(.PostToolUse, `{"rewrite":{"path":"a"}}`, &res3)
	testing.expect_value(t, res3.rewrite_args, "")
}

@(test)
test_apply_hook_output_first_decision_wins :: proc(t: ^testing.T) {
	res: Result
	apply_hook_output(.PermissionRequest, `{"decision":"deny","reason":"first"}`, &res)
	apply_hook_output(.PermissionRequest, `{"decision":"allow"}`, &res)
	testing.expect_value(t, res.decision, "deny")
	testing.expect_value(t, res.reason, "first")
	result_destroy(&res)
}
