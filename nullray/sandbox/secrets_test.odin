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
test_secret_empty_path_not_blocked :: proc(t: ^testing.T) {
	os.unset_env(constants.ENV_SECRETS_ALLOW)
	testing.expect(t, !path_is_secret_blocked(""))
}

@(test)
test_secret_basename_matrix :: proc(t: ^testing.T) {
	os.unset_env(constants.ENV_SECRETS_ALLOW)
	blocked := []string{
		"/tmp/x/.env",
		"/tmp/x/.env.production",
		"/tmp/x/.ENV",
		"/tmp/x/credentials.json",
		"/tmp/x/secrets.yaml",
		"/tmp/x/.npmrc",
		"/tmp/x/.netrc",
		"/tmp/x/id_rsa",
		"/tmp/x/id_ed25519",
		"/tmp/x/private.key",
		"/tmp/x/service-account.json",
		"/tmp/x/cert.pem",
		"/tmp/x/store.p12",
		"/tmp/x/app.keystore",
		"/home/u/.ssh/config",
		"/home/u/.aws/credentials",
		"/home/u/.gnupg/secring.gpg",
		"/home/u/.kube/config",
		"/opt/secrets/token",
		"/opt/.secrets/token",
	}
	for p in blocked {
		testing.expectf(t, path_is_secret_blocked(p), "expected blocked %s", p)
	}
	testing.expect(t, !path_is_secret_blocked("/tmp/x/readme.md"))
	testing.expect(t, !path_is_secret_blocked("/tmp/x/src/main.odin"))
}

@(test)
test_secret_allow_override :: proc(t: ^testing.T) {
	os.set_env(constants.ENV_SECRETS_ALLOW, "/tmp/proj/.env")
	defer os.unset_env(constants.ENV_SECRETS_ALLOW)
	testing.expect(t, !path_is_secret_blocked("/tmp/proj/.env"))
}

@(test)
test_secret_allow_basename_dot_env_current :: proc(t: ^testing.T) {
	os.set_env(constants.ENV_SECRETS_ALLOW, ".env")
	defer os.unset_env(constants.ENV_SECRETS_ALLOW)
	// Relative allow is joined to cwd first, so bare .env is not a global basename unlock.
	testing.expect(t, path_is_secret_blocked("/tmp/anywhere/.env"))
}

@(test)
test_secret_allow_star_prefix_current :: proc(t: ^testing.T) {
	os.set_env(constants.ENV_SECRETS_ALLOW, "*.env")
	defer os.unset_env(constants.ENV_SECRETS_ALLOW)
	// *.env does not basename-match .env today (base is literal *.env).
	testing.expect(t, path_is_secret_blocked("/tmp/proj/.env"))
}

@(test)
test_shell_secret_cat :: proc(t: ^testing.T) {
	os.unset_env(constants.ENV_SECRETS_ALLOW)
	blocked, hint := shell_mentions_secret("cat .env")
	testing.expect(t, blocked)
	testing.expect(t, len(hint) > 0)
}

@(test)
test_shell_secret_abs_env_local :: proc(t: ^testing.T) {
	os.unset_env(constants.ENV_SECRETS_ALLOW)
	blocked, hint := shell_mentions_secret("cat /tmp/x/.env.local")
	testing.expect(t, blocked)
	testing.expect(t, len(hint) > 0)
}

@(test)
test_shell_secret_quote_concat_current :: proc(t: ^testing.T) {
	os.unset_env(constants.ENV_SECRETS_ALLOW)
	// fields() tokenization misses quote-split names today.
	blocked, _ := shell_mentions_secret("cat .e''nv")
	testing.expect(t, !blocked)
}

@(test)
test_shell_secret_redir_no_space_substring :: proc(t: ^testing.T) {
	os.unset_env(constants.ENV_SECRETS_ALLOW)
	blocked, _ := shell_mentions_secret("cat<.env")
	testing.expect(t, blocked)
}

@(test)
test_shell_secret_var_indirection_current :: proc(t: ^testing.T) {
	os.unset_env(constants.ENV_SECRETS_ALLOW)
	blocked, _ := shell_mentions_secret("x=.env; cat $x")
	// Substring ".env" in the command still trips the name scan.
	testing.expect(t, blocked)
}

@(test)
test_secret_homoglyph_env_current :: proc(t: ^testing.T) {
	os.unset_env(constants.ENV_SECRETS_ALLOW)
	// Cyrillic ye in place of Latin e: not matched by ASCII heuristics today.
	cyrillic := "/tmp/proj/.еnv"
	testing.expect(t, !path_is_secret_blocked(cyrillic))
}

@(test)
test_secret_trailing_space_basename_current :: proc(t: ^testing.T) {
	os.unset_env(constants.ENV_SECRETS_ALLOW)
	testing.expect(t, !path_is_secret_blocked("/tmp/proj/.env "))
}
