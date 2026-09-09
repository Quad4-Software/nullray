// SPDX-License-Identifier: 0BSD
package sandbox

import "core:os"
import "core:strings"
import "core:testing"
import "nullray:constants"

@(test)
test_redact_home_and_user :: proc(t: ^testing.T) {
	had_r, prev_r := test_env_set(constants.ENV_PRIVACY_REDACT, "1")
	had_h, prev_h := test_env_set("HOME", "/home/user1")
	had_u, prev_u := test_env_set("USER", "user1")
	defer {
		test_env_restore(constants.ENV_PRIVACY_REDACT, had_r, prev_r)
		test_env_restore("HOME", had_h, prev_h)
		test_env_restore("USER", had_u, prev_u)
	}

	out := redact_secrets("path /home/user1/projects/nullray and user1 ok")
	defer delete(out)
	testing.expect(t, !strings.contains(out, "/home/user1"))
	testing.expect(t, strings.contains(out, "~") || strings.contains(out, "<user>"))
}

@(test)
test_redact_disabled :: proc(t: ^testing.T) {
	had_r, prev_r := test_env_set(constants.ENV_PRIVACY_REDACT, "0")
	had_h, prev_h := test_env_set("HOME", "/home/user1")
	had_u, prev_u := test_env_set("USER", "user1")
	defer {
		test_env_restore(constants.ENV_PRIVACY_REDACT, had_r, prev_r)
		test_env_restore("HOME", had_h, prev_h)
		test_env_restore("USER", had_u, prev_u)
	}
	src := "path /home/user1/projects and user1"
	out := redact_secrets(src)
	defer delete(out)
	testing.expect_value(t, out, src)
}

@(test)
test_redact_username_token_boundaries :: proc(t: ^testing.T) {
	had_r, prev_r := test_env_set(constants.ENV_PRIVACY_REDACT, "1")
	had_h, prev_h := test_env_set("HOME", "/home/user1")
	had_u, prev_u := test_env_set("USER", "user1")
	defer {
		test_env_restore(constants.ENV_PRIVACY_REDACT, had_r, prev_r)
		test_env_restore("HOME", had_h, prev_h)
		test_env_restore("USER", had_u, prev_u)
	}
	out := redact_secrets("user1foo /home/user1/x user1\n")
	defer delete(out)
	testing.expect(t, strings.contains(out, "user1foo"))
	testing.expect(t, !strings.contains(out, "/home/user1"))
	testing.expect(t, strings.contains(out, "<user>"))
}

@(test)
test_redact_macos_windows_paths_current :: proc(t: ^testing.T) {
	had_r, prev_r := test_env_set(constants.ENV_PRIVACY_REDACT, "1")
	had_h, prev_h := test_env_set("HOME", "/home/user1")
	had_u, prev_u := test_env_set("USER", "user1")
	defer {
		test_env_restore(constants.ENV_PRIVACY_REDACT, had_r, prev_r)
		test_env_restore("HOME", had_h, prev_h)
		test_env_restore("USER", had_u, prev_u)
	}
	src := "/Users/user1/proj C:\\Users\\user1\\proj"
	out := redact_secrets(src)
	defer delete(out)
	// HOME rewrite is Linux-path only. Username tokens still replace.
	testing.expect(t, strings.contains(out, "/Users/"))
	testing.expect(t, strings.contains(out, "C:\\Users\\"))
}

@(test)
test_redact_empty_passthrough :: proc(t: ^testing.T) {
	had_r, prev_r := test_env_set(constants.ENV_PRIVACY_REDACT, "1")
	defer test_env_restore(constants.ENV_PRIVACY_REDACT, had_r, prev_r)
	out := redact_secrets("")
	defer delete(out)
	testing.expect_value(t, out, "")
}

@(test)
test_redact_secrets_temp_allocator :: proc(t: ^testing.T) {
	had_r, prev_r := test_env_set(constants.ENV_PRIVACY_REDACT, "1")
	had_h, prev_h := test_env_set("HOME", "/home/user1")
	had_u, prev_u := test_env_set("USER", "user1")
	defer {
		test_env_restore(constants.ENV_PRIVACY_REDACT, had_r, prev_r)
		test_env_restore("HOME", had_h, prev_h)
		test_env_restore("USER", had_u, prev_u)
	}
	out := redact_secrets("README.md /home/user1/x user1", context.temp_allocator)
	testing.expect(t, !strings.contains(out, "/home/user1"))
	testing.expect(t, len(out) > 0)
}

@(test)
test_redact_secret_tokens :: proc(t: ^testing.T) {
	had_r, prev_r := test_env_set(constants.ENV_PRIVACY_REDACT, "1")
	defer test_env_restore(constants.ENV_PRIVACY_REDACT, had_r, prev_r)
	out := redact_secrets("key sk-abcDEF123 and api_key=supersecret")
	defer delete(out)
	testing.expect(t, !strings.contains(out, "sk-abcDEF123"))
	testing.expect(t, !strings.contains(out, "supersecret"))
	testing.expect(t, strings.contains(out, REDACTED_SECRET))
}

@(test)
test_redact_proxy_userinfo :: proc(t: ^testing.T) {
	had_r, prev_r := test_env_set(constants.ENV_PRIVACY_REDACT, "1")
	defer test_env_restore(constants.ENV_PRIVACY_REDACT, had_r, prev_r)
	out := redact_secrets("via http://user:pass@proxy.example:8080/x")
	defer delete(out)
	testing.expect(t, !strings.contains(out, "user:pass"))
	testing.expect(t, strings.contains(out, REDACTED_SECRET))
}

@(test)
test_privacy_redact_enabled_gate :: proc(t: ^testing.T) {
	had, prev := test_env_unset(constants.ENV_PRIVACY_REDACT)
	defer test_env_restore(constants.ENV_PRIVACY_REDACT, had, prev)

	os.set_env(constants.ENV_PRIVACY_REDACT, "off")
	testing.expect(t, !privacy_redact_enabled())
	os.set_env(constants.ENV_PRIVACY_REDACT, "on")
	testing.expect(t, privacy_redact_enabled())
}
