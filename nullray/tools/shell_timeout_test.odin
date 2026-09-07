// SPDX-License-Identifier: 0BSD
package tools

import "core:os"
import "core:testing"
import "nullray:constants"

@(test)
test_shell_timeout_default_interactive :: proc(t: ^testing.T) {
	os.unset_env(constants.ENV_AUTO)
	os.unset_env(constants.ENV_SHELL_TIMEOUT_MS)
	testing.expect_value(t, shell_timeout_ms_default(), constants.SHELL_TIMEOUT_MS)
}

@(test)
test_shell_timeout_auto_default :: proc(t: ^testing.T) {
	os.set_env(constants.ENV_AUTO, "1")
	os.unset_env(constants.ENV_SHELL_TIMEOUT_MS)
	defer os.unset_env(constants.ENV_AUTO)
	testing.expect_value(t, shell_timeout_ms_default(), constants.AUTO_SHELL_TIMEOUT_MS)
}

@(test)
test_shell_timeout_env_override :: proc(t: ^testing.T) {
	os.set_env(constants.ENV_SHELL_TIMEOUT_MS, "120000")
	defer os.unset_env(constants.ENV_SHELL_TIMEOUT_MS)
	testing.expect_value(t, shell_timeout_ms_default(), 120000)
}

@(test)
test_shell_timeout_from_args :: proc(t: ^testing.T) {
	os.unset_env(constants.ENV_AUTO)
	os.unset_env(constants.ENV_SHELL_TIMEOUT_MS)
	ms, err := shell_timeout_ms_from_args(`{"command":"true","timeout_ms":"45000"}`)
	testing.expect_value(t, err, "")
	testing.expect_value(t, ms, 45000)
}
