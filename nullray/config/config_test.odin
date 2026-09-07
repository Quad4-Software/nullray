// SPDX-License-Identifier: 0BSD
package config

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"
import "nullray:constants"

@(test)
test_merge_env_body_preserves_comments_and_unknown :: proc(t: ^testing.T) {
	existing := "# header\nFOO=bar\n# mid\nKEEP=1\n"
	kvs := []Env_KV{
		{key = "NULLRAY_PROVIDER", val = "openrouter"},
		{key = "FOO", val = "baz"},
	}
	out := merge_env_body(existing, kvs, context.allocator)
	defer delete(out)
	testing.expect(t, strings.contains(out, "# header"))
	testing.expect(t, strings.contains(out, "# mid"))
	testing.expect(t, strings.contains(out, "KEEP=1"))
	testing.expect(t, strings.contains(out, "FOO=baz"))
	testing.expect(t, strings.contains(out, "NULLRAY_PROVIDER=openrouter"))
	testing.expect(t, !strings.contains(out, "FOO=bar"))
}

@(test)
test_merge_env_keys_roundtrip_file :: proc(t: ^testing.T) {
	tmp, terr := os.temp_directory(context.temp_allocator)
	testing.expect(t, terr == nil)
	dir, jerr := filepath.join({tmp, "nullray-env-test"}, context.temp_allocator)
	testing.expect(t, jerr == nil)
	_ = os.make_directory_all(dir)
	path, perr := filepath.join({dir, "env"}, context.temp_allocator)
	testing.expect(t, perr == nil)
	_ = os.remove(path)

	seed := "# seed\nOLD=1\n"
	testing.expect(t, os.write_entire_file(path, transmute([]byte)seed) == nil)

	kvs := []Env_KV{
		{key = constants.ENV_PROVIDER, val = "ollama"},
		{key = constants.ENV_MODEL, val = "gemma3:4b"},
		{key = constants.ENV_REASONING, val = "low"},
		{key = constants.ENV_SETUP_DONE, val = "1"},
	}
	err := merge_env_keys(kvs, path, false)
	testing.expect_value(t, err, "")

	data, rerr := os.read_entire_file(path, context.temp_allocator)
	testing.expect(t, rerr == nil)
	body := string(data)
	testing.expect(t, strings.contains(body, "# seed"))
	testing.expect(t, strings.contains(body, "OLD=1"))
	testing.expect(t, strings.contains(body, "NULLRAY_PROVIDER=ollama"))
	testing.expect(t, strings.contains(body, "NULLRAY_SETUP_DONE=1"))
}

@(test)
test_setup_done_from_env :: proc(t: ^testing.T) {
	os.unset_env(constants.ENV_SETUP_DONE)
	testing.expect(t, !setup_done_from_env())
	os.set_env(constants.ENV_SETUP_DONE, "1")
	testing.expect(t, setup_done_from_env())
	os.set_env(constants.ENV_SETUP_DONE, "0")
	testing.expect(t, !setup_done_from_env())
	os.unset_env(constants.ENV_SETUP_DONE)
}
