// SPDX-License-Identifier: 0BSD
package sandbox

import "core:os"
import "core:path/filepath"
import "core:testing"
import "nullray:constants"

@(test)
test_docs_enabled_default_on :: proc(t: ^testing.T) {
	had, prev := test_env_unset(constants.ENV_DOCS)
	defer test_env_restore(constants.ENV_DOCS, had, prev)
	testing.expect(t, docs_enabled_from_env())
}

@(test)
test_docs_enabled_off :: proc(t: ^testing.T) {
	had, prev := test_env_set(constants.ENV_DOCS, "0")
	defer test_env_restore(constants.ENV_DOCS, had, prev)
	testing.expect(t, !docs_enabled_from_env())
}

@(test)
test_docs_append_skips_when_disabled :: proc(t: ^testing.T) {
	had, prev := test_env_set(constants.ENV_DOCS, "off")
	defer test_env_restore(constants.ENV_DOCS, had, prev)
	list := make([dynamic]string)
	defer {
		for p in list {
			delete(p)
		}
		delete(list)
	}
	docs_append_ro_paths(&list)
	testing.expect(t, len(list) == 0)
}

@(test)
test_docs_append_finds_tealdeer_cache :: proc(t: ^testing.T) {
	root := "/tmp/nullray-docs-ro-test"
	_ = os.remove_all(root)
	testing.expect(t, os.make_directory_all(root) == nil)
	defer os.remove_all(root)
	cache, _ := filepath.join({root, "tealdeer"}, context.temp_allocator)
	testing.expect(t, os.make_directory_all(cache) == nil)

	had_d, prev_d := test_env_unset(constants.ENV_DOCS)
	had_x, prev_x := test_env_set("XDG_CACHE_HOME", root)
	had_h, prev_h := test_env_set("HOME", "/tmp/nullray-docs-home-absent")
	defer {
		test_env_restore(constants.ENV_DOCS, had_d, prev_d)
		test_env_restore("XDG_CACHE_HOME", had_x, prev_x)
		test_env_restore("HOME", had_h, prev_h)
	}

	list := make([dynamic]string)
	defer {
		for p in list {
			delete(p)
		}
		delete(list)
	}
	docs_append_ro_paths(&list)
	found := false
	for p in list {
		if p == cache {
			found = true
		}
		testing.expect(t, p[0] == '/')
		testing.expect(t, p != "/tmp/nullray-docs-home-absent")
	}
	testing.expect(t, found)
}

@(test)
test_config_includes_docs_ro_by_default :: proc(t: ^testing.T) {
	root := "/tmp/nullray-docs-cfg-test"
	_ = os.remove_all(root)
	testing.expect(t, os.make_directory_all(root) == nil)
	defer os.remove_all(root)
	cache, _ := filepath.join({root, "tealdeer"}, context.temp_allocator)
	testing.expect(t, os.make_directory_all(cache) == nil)

	had_d, prev_d := test_env_unset(constants.ENV_DOCS)
	had_x, prev_x := test_env_set("XDG_CACHE_HOME", root)
	had_ops, prev_ops := test_env_unset(constants.ENV_OPS)
	defer {
		test_env_restore(constants.ENV_DOCS, had_d, prev_d)
		test_env_restore("XDG_CACHE_HOME", had_x, prev_x)
		test_env_restore(constants.ENV_OPS, had_ops, prev_ops)
	}
	cfg := config_from_env()
	defer config_destroy(&cfg)
	found := false
	for p in cfg.extra_ro {
		if p == cache {
			found = true
		}
	}
	testing.expect(t, found)
}
