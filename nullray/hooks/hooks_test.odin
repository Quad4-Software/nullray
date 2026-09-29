// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package hooks

import "core:testing"

@(test)
test_event_names_match_config_keys :: proc(t: ^testing.T) {
	testing.expect_value(t, event_name(.PreToolUse), "PreToolUse")
	testing.expect_value(t, event_name(.PostToolUse), "PostToolUse")
	testing.expect_value(t, event_name(.SessionStart), "SessionStart")
	testing.expect_value(t, event_name(.SessionEnd), "SessionEnd")
	testing.expect_value(t, event_name(.Stop), "Stop")
	testing.expect_value(t, event_name(.PreCommit), "PreCommit")
}

@(test)
test_run_command_closes_stdin_eof :: proc(t: ^testing.T) {
	// Commands reading stdin to EOF must finish inside the timeout; the
	// writer thread closes the pipe write end after delivering the input.
	code, timed, _ := run_command("grep -q marker_xyz", `{"a":"marker_xyz"}`)
	testing.expectf(t, !timed && code == 0, "grep match: code=%d timed=%v", code, timed)

	code2, timed2, _ := run_command("grep -q marker_xyz", `{"a":"other"}`)
	testing.expectf(t, !timed2 && code2 == 1, "grep miss: code=%d timed=%v", code2, timed2)

	code3, timed3, _ := run_command("cat > /dev/null", `{"big":"payload"}`)
	testing.expectf(t, !timed3 && code3 == 0, "cat eof: code=%d timed=%v", code3, timed3)
}

@(test)
test_run_command_exit2_blocks :: proc(t: ^testing.T) {
	code, timed, _ := run_command("exit 2", "")
	testing.expectf(t, code == 2 && !timed, "code=%d timed=%v", code, timed)
}
