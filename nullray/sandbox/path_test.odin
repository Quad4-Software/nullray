// SPDX-License-Identifier: 0BSD
package sandbox

import "core:os"
import "core:path/filepath"
import "core:testing"
import "nullray:constants"

@(test)
test_path_beneath_equal_and_child :: proc(t: ^testing.T) {
	testing.expect(t, path_beneath("/tmp/ws", "/tmp/ws"))
	testing.expect(t, path_beneath("/tmp/ws/a", "/tmp/ws"))
	testing.expect(t, path_beneath("/tmp/ws/a/b", "/tmp/ws"))
}

@(test)
test_path_beneath_rejects_sibling_prefix :: proc(t: ^testing.T) {
	testing.expect(t, !path_beneath("/tmp/ws_evil", "/tmp/ws"))
	testing.expect(t, !path_beneath("/tmp/ws_evil/x", "/tmp/ws"))
	testing.expect(t, !path_beneath("/tmp/ws2", "/tmp/ws"))
}

@(test)
test_path_beneath_trailing_slash_root :: proc(t: ^testing.T) {
	testing.expect(t, path_beneath("/tmp/ws/a", "/tmp/ws/"))
	testing.expect(t, !path_beneath("/tmp/ws_evil", "/tmp/ws/"))
}

@(test)
test_path_allowed_secret_short_circuit :: proc(t: ^testing.T) {
	os.unset_env(constants.ENV_SECRETS_ALLOW)
	s := test_state_with_allows({"/tmp/ws"}, {}, true)
	defer state_destroy(&s)
	testing.expect(t, !path_allowed(&s, "/tmp/ws/.env", false))
	testing.expect(t, !path_allowed(&s, "/tmp/ws/id_rsa", true))
}

@(test)
test_path_allowed_when_not_applied :: proc(t: ^testing.T) {
	os.unset_env(constants.ENV_SECRETS_ALLOW)
	s := test_state_with_allows({"/tmp/ws"}, {}, false)
	defer state_destroy(&s)
	testing.expect(t, path_allowed(&s, "/etc/passwd", false))
	testing.expect(t, path_allowed(&s, "/tmp/ws/main.odin", true))
	testing.expect(t, !path_allowed(&s, "/tmp/ws/.env", false))
}

@(test)
test_path_allowed_rw_vs_ro :: proc(t: ^testing.T) {
	os.unset_env(constants.ENV_SECRETS_ALLOW)
	s := test_state_with_allows({"/tmp/ws"}, {"/usr"}, true)
	defer state_destroy(&s)
	testing.expect(t, path_allowed(&s, "/tmp/ws/a.odin", true))
	testing.expect(t, path_allowed(&s, "/tmp/ws/a.odin", false))
	testing.expect(t, path_allowed(&s, "/usr/bin/ls", false))
	testing.expect(t, !path_allowed(&s, "/usr/bin/ls", true))
	testing.expect(t, !path_allowed(&s, "/etc/hosts", false))
	testing.expect(t, !path_allowed(&s, "/tmp/ws_evil/x", false))
}

@(test)
test_path_allowed_nil_state :: proc(t: ^testing.T) {
	os.unset_env(constants.ENV_SECRETS_ALLOW)
	testing.expect(t, path_allowed(nil, "/tmp/ok", false))
	testing.expect(t, !path_allowed(nil, "/tmp/.env", false))
}

@(test)
test_path_secret_after_clean_traversal :: proc(t: ^testing.T) {
	os.unset_env(constants.ENV_SECRETS_ALLOW)
	clean, _ := filepath.clean("/tmp/ws/a/../../.ssh/id_rsa", context.temp_allocator)
	testing.expect(t, path_is_secret_blocked(clean))
	testing.expect(t, path_is_secret_blocked("/tmp/ws/a/../../.ssh/id_rsa"))
}

@(test)
test_shell_allowed_fs_modes :: proc(t: ^testing.T) {
	s_off := test_state_with_allows({}, {}, false)
	defer state_destroy(&s_off)
	testing.expect(t, shell_allowed(&s_off))

	s_rw := test_state_with_allows({"/tmp/ws"}, {}, true)
	defer state_destroy(&s_rw)
	s_rw.fs = .RW
	testing.expect(t, shell_allowed(&s_rw))

	s_ro := test_state_with_allows({"/tmp/ws"}, {}, true)
	defer state_destroy(&s_ro)
	s_ro.fs = .RO
	testing.expect(t, !shell_allowed(&s_ro))
}
