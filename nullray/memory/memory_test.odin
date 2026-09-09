// SPDX-License-Identifier: 0BSD
package memory

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"
import "core:time"
import "nullray:constants"

Test_Ws :: struct {
	ws:   string,
	prev: string,
	had:  bool,
}

@(private)
test_memory_ws_begin :: proc(t: ^testing.T) -> Test_Ws {
	ctx: Test_Ws
	base := "/tmp"
	if td, ok := os.lookup_env("TMPDIR", context.temp_allocator); ok && len(td) > 0 {
		base = td
	}
	ctx.ws = fmt.tprintf("%s/nullray-memory-test-%d", base, time.time_to_unix(time.now()))
	_ = os.remove_all(ctx.ws)
	testing.expect(t, os.make_directory_all(ctx.ws) == nil)
	ctx.prev, ctx.had = os.lookup_env(constants.ENV_WORKSPACE, context.allocator)
	os.set_env(constants.ENV_WORKSPACE, ctx.ws)
	return ctx
}

@(private)
test_memory_ws_end :: proc(ctx: Test_Ws) {
	if ctx.had {
		os.set_env(constants.ENV_WORKSPACE, ctx.prev)
		delete(ctx.prev)
	} else {
		os.unset_env(constants.ENV_WORKSPACE)
	}
	os.remove_all(ctx.ws)
}

@(private)
test_memory_dir :: proc(t: ^testing.T, ws: string, allocator := context.allocator) -> string {
	path, err := filepath.join({ws, constants.MEMORY_DIR}, allocator)
	testing.expect(t, err == nil)
	return path
}

@(test)
test_put_get_roundtrip :: proc(t: ^testing.T) {
	ctx := test_memory_ws_begin(t)
	defer test_memory_ws_end(ctx)

	msg, err := Put("pref.editor", "use tabs")
	defer delete(msg)
	defer delete(err)
	testing.expect_value(t, err, "")
	testing.expect(t, strings.has_prefix(msg, "ok"))

	got, get_err := Get("pref.editor")
	defer delete(got)
	defer delete(get_err)
	testing.expect_value(t, get_err, "")
	testing.expect_value(t, got, "use tabs")
}

@(test)
test_delete_and_forget :: proc(t: ^testing.T) {
	ctx := test_memory_ws_begin(t)
	defer test_memory_ws_end(ctx)

	_, err := Put("build.cmd", "make test")
	defer delete(err)
	testing.expect_value(t, err, "")

	del_msg, del_err := Delete("build.cmd")
	defer delete(del_msg)
	defer delete(del_err)
	testing.expect_value(t, del_err, "")
	testing.expect_value(t, del_msg, "ok")

	_, get_err := Get("build.cmd")
	defer delete(get_err)
	testing.expect(t, len(get_err) > 0)

	_, put_err := Put("arch.layer", "sandbox first")
	defer delete(put_err)
	testing.expect_value(t, put_err, "")

	forget_msg, forget_err := Forget("arch.layer")
	defer delete(forget_msg)
	defer delete(forget_err)
	testing.expect_value(t, forget_err, "")
	testing.expect_value(t, forget_msg, "ok")
}

@(test)
test_compact_on_delete :: proc(t: ^testing.T) {
	ctx := test_memory_ws_begin(t)
	defer test_memory_ws_end(ctx)

	_, err := Put("pref.a", "one")
	defer delete(err)
	testing.expect_value(t, err, "")
	_, err = Put("pref.a", "two")
	defer delete(err)
	testing.expect_value(t, err, "")

	_, del_err := Delete("pref.a")
	defer delete(del_err)
	testing.expect_value(t, del_err, "")

	dir := test_memory_dir(t, ctx.ws)
	defer delete(dir)
	path, _ := filepath.join({dir, "entries.jsonl"}, context.temp_allocator)
	data, read_err := os.read_entire_file(path, context.temp_allocator)
	testing.expect(t, read_err == nil)
	lines := 0
	for line in strings.split_lines(string(data), context.temp_allocator) {
		if len(strings.trim_space(line)) > 0 {
			lines += 1
		}
	}
	testing.expect_value(t, lines, 0)
}

@(test)
test_search_ranking :: proc(t: ^testing.T) {
	ctx := test_memory_ws_begin(t)
	defer test_memory_ws_end(ctx)

	_, err := Put("user.alice", "likes odin")
	defer delete(err)
	testing.expect_value(t, err, "")
	_, err = Put("debt.todo", "fix odin warnings")
	defer delete(err)
	testing.expect_value(t, err, "")

	out := Search("odin", 10)
	defer delete(out)
	testing.expect(t, strings.contains(out, "user.alice"))
	testing.expect(t, strings.contains(out, "debt.todo"))
	testing.expect(t, strings.contains(out, "match:key") || strings.contains(out, "match:value"))
}

@(test)
test_list_richer_format :: proc(t: ^testing.T) {
	ctx := test_memory_ws_begin(t)
	defer test_memory_ws_end(ctx)

	_, err := Put("pref.fmt", "hello world")
	defer delete(err)
	testing.expect_value(t, err, "")

	out := List("")
	defer delete(out)
	testing.expect(t, strings.contains(out, "pref.fmt"))
	testing.expect(t, strings.contains(out, "hello world"))
	testing.expect(t, strings.contains(out, "|"))
}

@(test)
test_digest_includes_updated :: proc(t: ^testing.T) {
	ctx := test_memory_ws_begin(t)
	defer test_memory_ws_end(ctx)

	_, err := Put("pref.digest", "remember this")
	defer delete(err)
	testing.expect_value(t, err, "")

	entries := load_entries(context.temp_allocator)
	defer destroy_entries(&entries, context.temp_allocator)
	digest := digest_from_entries(entries[:], 4_000)
	defer delete(digest)
	testing.expect(t, strings.contains(digest, "pref.digest"))
	testing.expect(t, strings.contains(digest, "updated"))
}

@(test)
test_ephemeral_allows_explicit_put :: proc(t: ^testing.T) {
	ctx := test_memory_ws_begin(t)
	defer test_memory_ws_end(ctx)

	prev, had := os.lookup_env(constants.ENV_EPHEMERAL, context.allocator)
	os.set_env(constants.ENV_EPHEMERAL, "1")
	defer {
		if had {
			os.set_env(constants.ENV_EPHEMERAL, prev)
			delete(prev)
		} else {
			os.unset_env(constants.ENV_EPHEMERAL)
		}
	}

	msg, err := Put("pref.skip", "persists")
	defer delete(msg)
	defer delete(err)
	testing.expect_value(t, err, "")
	testing.expect(t, strings.has_prefix(msg, "ok"))

	got, get_err := Get("pref.skip")
	defer delete(got)
	defer delete(get_err)
	testing.expect_value(t, get_err, "")
	testing.expect_value(t, got, "persists")
}

@(test)
test_secret_rejected :: proc(t: ^testing.T) {
	ctx := test_memory_ws_begin(t)
	defer test_memory_ws_end(ctx)

	_, err := Put("pref.secret", "api_key=supersecret")
	defer delete(err)
	testing.expect(t, len(err) > 0)
	testing.expect(t, strings.contains(err, "secret"))
}

@(test)
test_topic_file_for_long_value :: proc(t: ^testing.T) {
	ctx := test_memory_ws_begin(t)
	defer test_memory_ws_end(ctx)

	long_value := strings.repeat("x", constants.MEMORY_TOPIC_CHARS + 20, context.temp_allocator)
	_, err := Put("arch.long", long_value)
	defer delete(err)
	testing.expect_value(t, err, "")

	dir := test_memory_dir(t, ctx.ws)
	defer delete(dir)
	topic_path, _ := filepath.join({dir, "topics", "arch.long.md"}, context.temp_allocator)
	data, read_err := os.read_entire_file(topic_path, context.temp_allocator)
	testing.expect(t, read_err == nil)
	testing.expect(t, strings.contains(string(data), long_value[:32]))
}

@(test)
test_key_prefix_warn :: proc(t: ^testing.T) {
	ctx := test_memory_ws_begin(t)
	defer test_memory_ws_end(ctx)

	msg, err := Put("misc.note", "unprefixed key")
	defer delete(msg)
	defer delete(err)
	testing.expect_value(t, err, "")
	testing.expect(t, strings.contains(msg, "unconventional"))
}
