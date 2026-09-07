// SPDX-License-Identifier: 0BSD
package sandbox

import "core:testing"
import "nullray:constants"

@(test)
test_apply_off_keeps_workspace :: proc(t: ^testing.T) {
	had_s, prev_s := test_env_set(constants.ENV_SANDBOX, "off")
	had_w, prev_w := test_env_set(constants.ENV_WORKSPACE, "/tmp/nullray-ws-off-test")
	defer {
		test_env_restore(constants.ENV_SANDBOX, had_s, prev_s)
		test_env_restore(constants.ENV_WORKSPACE, had_w, prev_w)
		state_destroy(&g_state)
		g_state = {}
	}
	cfg := config_from_env()
	defer config_destroy(&cfg)
	res := apply(cfg)
	testing.expect(t, res.ok)
	testing.expect(t, !res.applied)
	testing.expect_value(t, g_state.workspace, "/tmp/nullray-ws-off-test")
	testing.expect_value(t, g_state.mode, Mode.Off)
}
