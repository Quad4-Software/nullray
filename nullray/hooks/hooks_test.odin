// SPDX-License-Identifier: 0BSD
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
