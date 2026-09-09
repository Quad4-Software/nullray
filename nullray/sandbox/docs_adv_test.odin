// SPDX-License-Identifier: 0BSD
/*
Adversarial oracles for NULLRAY_DOCS path grants and docs tool inputs.
*/

package sandbox

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"
import "nullray:constants"

@(test)
test_adv_rustup_home_equals_home_rejected :: proc(t: ^testing.T) {
	fake_home := "/tmp/nullray-adv-rustup-home"
	_ = os.remove_all(fake_home)
	testing.expect(t, os.make_directory_all(fake_home) == nil)
	defer os.remove_all(fake_home)
	secret, _ := filepath.join({fake_home, ".ssh"}, context.temp_allocator)
	testing.expect(t, os.make_directory_all(secret) == nil)

	had_d, prev_d := test_env_unset(constants.ENV_DOCS)
	had_r, prev_r := test_env_set("RUSTUP_HOME", fake_home)
	had_h, prev_h := test_env_set("HOME", fake_home)
	had_x, prev_x := test_env_set("XDG_CACHE_HOME", "/tmp/nullray-adv-noxdg")
	defer {
		test_env_restore(constants.ENV_DOCS, had_d, prev_d)
		test_env_restore("RUSTUP_HOME", had_r, prev_r)
		test_env_restore("HOME", had_h, prev_h)
		test_env_restore("XDG_CACHE_HOME", had_x, prev_x)
	}

	list := make([dynamic]string)
	defer {
		for p in list {
			delete(p)
		}
		delete(list)
	}
	docs_append_ro_paths(&list)
	for p in list {
		testing.expectf(t, p != fake_home, "RUSTUP_HOME=$HOME must not grant home: %s", p)
		testing.expectf(t, p != secret, "must not grant .ssh: %s", p)
	}
}

@(test)
test_adv_goroot_equals_home_rejected :: proc(t: ^testing.T) {
	fake := "/tmp/nullray-adv-goroot-home"
	_ = os.remove_all(fake)
	testing.expect(t, os.make_directory_all(fake) == nil)
	defer os.remove_all(fake)

	had_d, prev_d := test_env_unset(constants.ENV_DOCS)
	had_g, prev_g := test_env_set("GOROOT", fake)
	had_h, prev_h := test_env_set("HOME", fake)
	had_x, prev_x := test_env_set("XDG_CACHE_HOME", "/tmp/nullray-adv-noxdg2")
	had_r, prev_r := test_env_unset("RUSTUP_HOME")
	defer {
		test_env_restore(constants.ENV_DOCS, had_d, prev_d)
		test_env_restore("GOROOT", had_g, prev_g)
		test_env_restore("HOME", had_h, prev_h)
		test_env_restore("XDG_CACHE_HOME", had_x, prev_x)
		test_env_restore("RUSTUP_HOME", had_r, prev_r)
	}

	list := make([dynamic]string)
	defer {
		for p in list {
			delete(p)
		}
		delete(list)
	}
	docs_append_ro_paths(&list)
	for p in list {
		testing.expectf(t, p != fake, "GOROOT=$HOME must not grant home: %s", p)
	}
}

@(test)
test_adv_xdg_cache_home_is_home_only_grants_tealdeer_subdir :: proc(t: ^testing.T) {
	home := "/tmp/nullray-adv-xdg-home"
	_ = os.remove_all(home)
	testing.expect(t, os.make_directory_all(home) == nil)
	defer os.remove_all(home)
	cache, _ := filepath.join({home, "tealdeer"}, context.temp_allocator)
	testing.expect(t, os.make_directory_all(cache) == nil)
	ssh, _ := filepath.join({home, ".ssh"}, context.temp_allocator)
	testing.expect(t, os.make_directory_all(ssh) == nil)

	had_d, prev_d := test_env_unset(constants.ENV_DOCS)
	had_x, prev_x := test_env_set("XDG_CACHE_HOME", home)
	had_h, prev_h := test_env_set("HOME", "/tmp/nullray-adv-unused-home")
	had_r, prev_r := test_env_unset("RUSTUP_HOME")
	had_g, prev_g := test_env_unset("GOROOT")
	defer {
		test_env_restore(constants.ENV_DOCS, had_d, prev_d)
		test_env_restore("XDG_CACHE_HOME", had_x, prev_x)
		test_env_restore("HOME", had_h, prev_h)
		test_env_restore("RUSTUP_HOME", had_r, prev_r)
		test_env_restore("GOROOT", had_g, prev_g)
	}

	list := make([dynamic]string)
	defer {
		for p in list {
			delete(p)
		}
		delete(list)
	}
	docs_append_ro_paths(&list)
	for p in list {
		testing.expectf(t, p != home, "must not grant XDG_CACHE_HOME root when it is a home stand-in: %s", p)
		testing.expectf(t, p != ssh, "must not grant .ssh: %s", p)
	}
	found := false
	for p in list {
		if p == cache {
			found = true
		}
	}
	testing.expect(t, found)
}

@(test)
test_adv_rustup_home_other_user_rejected :: proc(t: ^testing.T) {
	other := "/tmp/nullray-adv-other-user"
	_ = os.remove_all(other)
	testing.expect(t, os.make_directory_all(other) == nil)
	defer os.remove_all(other)

	had_d, prev_d := test_env_unset(constants.ENV_DOCS)
	had_r, prev_r := test_env_set("RUSTUP_HOME", other)
	had_h, prev_h := test_env_set("HOME", "/tmp/nullray-adv-my-home")
	had_x, prev_x := test_env_set("XDG_CACHE_HOME", "/tmp/nullray-adv-noxdg3")
	defer {
		test_env_restore(constants.ENV_DOCS, had_d, prev_d)
		test_env_restore("RUSTUP_HOME", had_r, prev_r)
		test_env_restore("HOME", had_h, prev_h)
		test_env_restore("XDG_CACHE_HOME", had_x, prev_x)
	}
	list := make([dynamic]string)
	defer {
		for p in list {
			delete(p)
		}
		delete(list)
	}
	docs_append_ro_paths(&list)
	for p in list {
		testing.expectf(t, p != other, "foreign RUSTUP_HOME must require EXTRA_RO: %s", p)
	}
}

@(test)
test_adv_never_grants_bare_home_by_default :: proc(t: ^testing.T) {
	home := "/tmp/nullray-adv-bare-home"
	_ = os.remove_all(home)
	testing.expect(t, os.make_directory_all(home) == nil)
	defer os.remove_all(home)

	had_d, prev_d := test_env_unset(constants.ENV_DOCS)
	had_h, prev_h := test_env_set("HOME", home)
	had_x, prev_x := test_env_set("XDG_CACHE_HOME", "/tmp/nullray-adv-empty-cache")
	had_xd, prev_xd := test_env_set("XDG_DATA_HOME", "/tmp/nullray-adv-empty-data")
	had_r, prev_r := test_env_unset("RUSTUP_HOME")
	had_c, prev_c := test_env_unset("CARGO_HOME")
	had_g, prev_g := test_env_unset("GOROOT")
	defer {
		test_env_restore(constants.ENV_DOCS, had_d, prev_d)
		test_env_restore("HOME", had_h, prev_h)
		test_env_restore("XDG_CACHE_HOME", had_x, prev_x)
		test_env_restore("XDG_DATA_HOME", had_xd, prev_xd)
		test_env_restore("RUSTUP_HOME", had_r, prev_r)
		test_env_restore("CARGO_HOME", had_c, prev_c)
		test_env_restore("GOROOT", had_g, prev_g)
	}

	list := make([dynamic]string)
	defer {
		for p in list {
			delete(p)
		}
		delete(list)
	}
	docs_append_ro_paths(&list)
	for p in list {
		testing.expectf(t, p != home, "bare HOME granted: %s", p)
	}
}

@(test)
test_adv_symlink_tealdeer_to_ssh_rejected :: proc(t: ^testing.T) {
	root := "/tmp/nullray-adv-symlink"
	_ = os.remove_all(root)
	testing.expect(t, os.make_directory_all(root) == nil)
	defer os.remove_all(root)
	ssh, _ := filepath.join({root, "ssh-store"}, context.temp_allocator)
	testing.expect(t, os.make_directory_all(ssh) == nil)
	cache_parent, _ := filepath.join({root, "cache"}, context.temp_allocator)
	testing.expect(t, os.make_directory_all(cache_parent) == nil)
	link, _ := filepath.join({cache_parent, "tealdeer"}, context.temp_allocator)
	testing.expect(t, os.symlink(ssh, link) == nil)

	had_d, prev_d := test_env_unset(constants.ENV_DOCS)
	had_x, prev_x := test_env_set("XDG_CACHE_HOME", cache_parent)
	had_h, prev_h := test_env_set("HOME", "/tmp/nullray-adv-sym-home")
	had_r, prev_r := test_env_unset("RUSTUP_HOME")
	had_g, prev_g := test_env_unset("GOROOT")
	defer {
		test_env_restore(constants.ENV_DOCS, had_d, prev_d)
		test_env_restore("XDG_CACHE_HOME", had_x, prev_x)
		test_env_restore("HOME", had_h, prev_h)
		test_env_restore("RUSTUP_HOME", had_r, prev_r)
		test_env_restore("GOROOT", had_g, prev_g)
	}

	list := make([dynamic]string)
	defer {
		for p in list {
			delete(p)
		}
		delete(list)
	}
	docs_append_ro_paths(&list)
	for p in list {
		testing.expectf(t, p != link, "symlink tealdeer must not be granted: %s", p)
		testing.expectf(t, p != ssh, "ssh-store must not be granted: %s", p)
	}
}

@(test)
test_adv_scrubbed_env_strips_secrets :: proc(t: ^testing.T) {
	had, prev := test_env_set("OPENROUTER_API_KEY", "sk-scrub-oracle")
	had_c, prev_c := test_env_set("COOKIE", "session=1")
	defer {
		test_env_restore("OPENROUTER_API_KEY", had, prev)
		test_env_restore("COOKIE", had_c, prev_c)
	}
	env := docs_scrubbed_env()
	defer docs_env_destroy(env)
	for e in env {
		testing.expectf(t, !strings.has_prefix(e, "OPENROUTER_API_KEY="), "leak: %s", e)
		testing.expectf(t, !strings.has_prefix(e, "COOKIE="), "leak: %s", e)
	}
}

@(test)
test_adv_go_child_env_strips_secrets_and_old_gocache :: proc(t: ^testing.T) {
	had, prev := test_env_set("OPENROUTER_API_KEY", "sk-test-leak-oracle")
	had_t, prev_t := test_env_set("GITHUB_TOKEN", "ghp_test")
	had_g, prev_g := test_env_set("GOCACHE", "/tmp/evil-gocache")
	had_p, prev_p := test_env_set("PATH", "/usr/bin:/bin")
	defer {
		test_env_restore("OPENROUTER_API_KEY", had, prev)
		test_env_restore("GITHUB_TOKEN", had_t, prev_t)
		test_env_restore("GOCACHE", had_g, prev_g)
		test_env_restore("PATH", had_p, prev_p)
	}
	env := docs_go_child_env()
	defer docs_env_destroy(env)
	saw_key := false
	saw_token := false
	saw_evil := false
	saw_new := false
	saw_path := false
	for e in env {
		if strings.has_prefix(e, "OPENROUTER_API_KEY=") {
			saw_key = true
		}
		if strings.has_prefix(e, "GITHUB_TOKEN=") {
			saw_token = true
		}
		if e == "GOCACHE=/tmp/evil-gocache" {
			saw_evil = true
		}
		if strings.has_prefix(e, "GOCACHE=") && strings.contains(e, "go-cache") {
			saw_new = true
		}
		if strings.has_prefix(e, "PATH=") {
			saw_path = true
		}
	}
	testing.expect(t, !saw_key)
	testing.expect(t, !saw_token)
	testing.expect(t, !saw_evil)
	testing.expect(t, saw_new)
	testing.expect(t, saw_path)
}
