// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Trust-store allow/deny/persist tests and the JSON string escaper used for
hook stdin and the store file itself.
*/

package hooks

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

@(private)
write_hooks_file :: proc(t: ^testing.T, dir, body: string) -> string {
	// make_directory_all returns .Exist when the dir already exists.
	merr := os.make_directory_all(dir)
	testing.expect(t, merr == nil || merr == .Exist)
	p, _ := filepath.join({dir, "hooks.json"}, context.temp_allocator)
	testing.expect(t, os.write_entire_file(p, transmute([]u8)body) == nil)
	return p
}

@(test)
test_write_json_string_roundtrip :: proc(t: ^testing.T) {
	payloads := []string{
		"plain",
		`quote " and backslash \`,
		"ctrl \x07\x1b\x0b\x01\x1f end",
		"tab\tnewline\ncarriage\r",
		"unicode: cafe\u00e9 \u20ac \U0001F600",
		"",
	}
	for s in payloads {
		b := strings.builder_make(context.temp_allocator)
		write_json_string(&b, s)
		// Wrap in an object like the hook stdin envelope does.
		env := strings.concatenate({`{"v":`, strings.to_string(b), `}`}, context.temp_allocator)
		doc, err := json.parse_string(env, .JSON, allocator = context.temp_allocator)
		testing.expectf(t, err == .None, "payload %q failed to parse: %v", s, err)
		obj, ok := doc.(json.Object)
		testing.expect(t, ok)
		got, gok := obj["v"].(json.String)
		testing.expect(t, gok)
		testing.expect_value(t, string(got), s)
	}
}

@(test)
test_trust_store_deny_grant_change :: proc(t: ^testing.T) {
	base := fmt.tprintf("/tmp/nullray-trust-test-%d", os.get_pid())
	cfg, _ := filepath.join({base, "cfg"}, context.temp_allocator)
	ws, _ := filepath.join({base, "ws", ".nullray"}, context.temp_allocator)
	defer os.remove_all(base)

	prev_xdg, had_xdg := os.lookup_env("XDG_CONFIG_HOME", context.allocator)
	defer {
		if had_xdg {
			os.set_env("XDG_CONFIG_HOME", prev_xdg)
			delete(prev_xdg)
		} else {
			os.unset_env("XDG_CONFIG_HOME")
		}
		hooks_trust_reset_for_test()
	}
	os.set_env("XDG_CONFIG_HOME", cfg)
	hooks_trust_reset_for_test()

	path := write_hooks_file(t, ws, `{"PreToolUse":["echo hi"]}`)

	// First sight: denied.
	testing.expect(t, !hooks_file_trusted(path))
	// Approval records the signature, the same stat passes.
	testing.expect(t, trust_grant_file(path))
	testing.expect(t, hooks_file_trusted(path))
	// The store file exists under the redirected config dir.
	store, _ := filepath.join({cfg, "nullray", TRUST_STORE_FILE}, context.temp_allocator)
	testing.expect(t, os.is_file(store))
	// Persisted: clearing in-memory state keeps the approval.
	hooks_trust_reset_for_test()
	testing.expect(t, hooks_file_trusted(path))
	// A rewrite invalidates the record (size differs at minimum).
	write_hooks_file(t, ws, `{"PreToolUse":["echo hi"],"Stop":["echo bye"]}`)
	testing.expect(t, !hooks_file_trusted(path))
	// Re-approval works on the new signature.
	testing.expect(t, trust_grant_file(path))
	testing.expect(t, hooks_file_trusted(path))
}

@(test)
test_trust_store_env_one_shot :: proc(t: ^testing.T) {
	base := fmt.tprintf("/tmp/nullray-trust-env-%d", os.get_pid())
	cfg, _ := filepath.join({base, "cfg"}, context.temp_allocator)
	ws, _ := filepath.join({base, "ws", ".nullray"}, context.temp_allocator)
	defer os.remove_all(base)

	prev_xdg, had_xdg := os.lookup_env("XDG_CONFIG_HOME", context.allocator)
	prev_trust, had_trust := os.lookup_env("NULLRAY_HOOKS_TRUST", context.allocator)
	defer {
		if had_xdg {
			os.set_env("XDG_CONFIG_HOME", prev_xdg)
			delete(prev_xdg)
		} else {
			os.unset_env("XDG_CONFIG_HOME")
		}
		if had_trust {
			os.set_env("NULLRAY_HOOKS_TRUST", prev_trust)
			delete(prev_trust)
		} else {
			os.unset_env("NULLRAY_HOOKS_TRUST")
		}
		hooks_trust_reset_for_test()
	}
	os.set_env("XDG_CONFIG_HOME", cfg)
	os.set_env("NULLRAY_HOOKS_TRUST", "1")
	hooks_trust_reset_for_test()

	path := write_hooks_file(t, ws, `{"PreToolUse":["echo hi"]}`)
	// One-shot env trust approves the first denied signature seen.
	testing.expect(t, hooks_file_trusted(path))
	// The env var stays set (worker threads must not unset_env) but the
	// one-shot flag is consumed: a changed file is denied again.
	write_hooks_file(t, ws, `{"PreToolUse":["echo hi"],"Stop":["x"]}`)
	testing.expect(t, !hooks_file_trusted(path))
}
