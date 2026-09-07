package sandbox

import "core:os"
import "core:strings"
import "core:testing"
import "nullray:constants"

@(test)
test_redact_home_and_user :: proc(t: ^testing.T) {
	os.set_env(constants.ENV_PRIVACY_REDACT, "1")
	os.set_env("HOME", "/home/user1")
	os.set_env("USER", "user1")
	defer os.unset_env(constants.ENV_PRIVACY_REDACT)

	out := redact_secrets("path /home/user1/projects/nullray and user1 ok")
	defer delete(out)
	testing.expect(t, !strings.contains(out, "/home/user1"))
	testing.expect(t, strings.contains(out, "~") || strings.contains(out, "<user>"))
}
