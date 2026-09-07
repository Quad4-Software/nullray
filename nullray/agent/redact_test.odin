// SPDX-License-Identifier: 0BSD
package agent

import "core:os"
import "core:strings"
import "core:testing"
import "nullray:constants"
import "nullray:sandbox"

@(test)
test_tool_result_redact_home :: proc(t: ^testing.T) {
	os.set_env(constants.ENV_PRIVACY_REDACT, "1")
	prev_h, had_h := os.lookup_env("HOME", context.allocator)
	prev_u, had_u := os.lookup_env("USER", context.allocator)
	os.set_env("HOME", "/home/user1")
	os.set_env("USER", "user1")
	defer {
		os.unset_env(constants.ENV_PRIVACY_REDACT)
		if had_h {
			os.set_env("HOME", prev_h)
			delete(prev_h)
		} else {
			os.unset_env("HOME")
		}
		if had_u {
			os.set_env("USER", prev_u)
			delete(prev_u)
		} else {
			os.unset_env("USER")
		}
	}

	raw := "wrote /home/user1/projects/nullray/main.odin"
	out := sandbox.redact_secrets(raw)
	defer delete(out)
	testing.expect(t, !strings.contains(out, "/home/user1"))
	testing.expect(t, strings.contains(out, "~") || strings.contains(out, "<user>"))
}
