// SPDX-License-Identifier: 0BSD
package sandbox

import "core:os"
import "core:testing"
import "nullray:constants"

@(test)
test_secret_env_blocked :: proc(t: ^testing.T) {
	os.unset_env(constants.ENV_SECRETS_ALLOW)
	testing.expect(t, path_is_secret_blocked("/tmp/proj/.env"))
	testing.expect(t, path_is_secret_blocked("/tmp/proj/.env.local"))
	testing.expect(t, path_is_secret_blocked("/home/x/.ssh/id_rsa"))
	testing.expect(t, !path_is_secret_blocked("/tmp/proj/main.odin"))
}

@(test)
test_secret_allow_override :: proc(t: ^testing.T) {
	os.set_env(constants.ENV_SECRETS_ALLOW, "/tmp/proj/.env")
	defer os.unset_env(constants.ENV_SECRETS_ALLOW)
	testing.expect(t, !path_is_secret_blocked("/tmp/proj/.env"))
}

@(test)
test_shell_secret_cat :: proc(t: ^testing.T) {
	os.unset_env(constants.ENV_SECRETS_ALLOW)
	blocked, hint := shell_mentions_secret("cat .env")
	testing.expect(t, blocked)
	testing.expect(t, len(hint) > 0)
}
