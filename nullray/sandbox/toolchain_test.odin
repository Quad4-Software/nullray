// SPDX-License-Identifier: 0BSD
package sandbox

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"
import "nullray:constants"

@(test)
test_toolchain_append_rw_go_cache :: proc(t: ^testing.T) {
	os.unset_env(constants.ENV_TOOLCHAIN)
	home, ok := os.lookup_env("HOME", context.temp_allocator)
	testing.expect(t, ok && len(home) > 0)
	list := make([dynamic]string, context.temp_allocator)
	toolchain_append_rw_paths(&list, context.temp_allocator)
	testing.expect(t, len(list) > 0)
	found_mod := false
	found_cache := false
	for p in list {
		if strings.contains(p, "go/pkg/mod") || strings.has_suffix(p, "pkg/mod") {
			found_mod = true
		}
		if strings.contains(p, "go-build") {
			found_cache = true
		}
	}
	testing.expect(t, found_mod || found_cache)
}

@(test)
test_toolchain_disabled :: proc(t: ^testing.T) {
	os.set_env(constants.ENV_TOOLCHAIN, "0")
	defer os.unset_env(constants.ENV_TOOLCHAIN)
	list := make([dynamic]string, context.temp_allocator)
	toolchain_append_rw_paths(&list, context.temp_allocator)
	testing.expect_value(t, len(list), 0)
	env := toolchain_shell_env(context.temp_allocator)
	testing.expect(t, env == nil)
}

@(test)
test_toolchain_shell_env_sets_gomodcache :: proc(t: ^testing.T) {
	os.unset_env(constants.ENV_TOOLCHAIN)
	env := toolchain_shell_env(context.allocator)
	defer toolchain_shell_env_destroy(env)
	testing.expect(t, len(env) > 0)
	found := false
	for e in env {
		if strings.has_prefix(e, "GOMODCACHE=") {
			found = true
			path := e[len("GOMODCACHE="):]
			testing.expect(t, filepath.is_abs(path))
		}
	}
	testing.expect(t, found)
}
