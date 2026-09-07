// SPDX-License-Identifier: 0BSD
package app

import "core:os"
import "core:testing"
import "nullray:config"
import "nullray:constants"

@(test)
test_setup_done_skips_needed :: proc(t: ^testing.T) {
	os.unset_env(constants.ENV_SETUP_DONE)
	testing.expect(t, !config.setup_done_from_env())
	os.set_env(constants.ENV_SETUP_DONE, "1")
	testing.expect(t, config.setup_done_from_env())
	os.unset_env(constants.ENV_SETUP_DONE)
}
