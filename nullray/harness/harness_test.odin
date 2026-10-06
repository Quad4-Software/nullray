// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package harness

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"
import "core:time"
import "nullray:constants"

@(private)
test_env_set :: proc(key, value: string) -> (had: bool, prev: string) {
	if v, ok := os.lookup_env(key, context.allocator); ok {
		had = true
		prev = v
	}
	os.set_env(key, value)
	return
}

@(private)
test_env_restore :: proc(key: string, had: bool, prev: string) {
	if had {
		os.set_env(key, prev)
		delete(prev)
	} else {
		os.unset_env(key)
	}
}

@(private)
test_append :: proc(list: ^[dynamic]Harness, id, bin: string, argv: []string, allocator := context.allocator) {
	h: Harness
	h.id = strings.clone(id, allocator)
	h.bin = strings.clone(bin, allocator)
	h.argv = make([dynamic]string, allocator)
	for a in argv {
		append(&h.argv, strings.clone(a, allocator))
	}
	append(list, h)
}

@(test)
test_config_parse_and_override :: proc(t: ^testing.T) {
	out := make([dynamic]Harness, context.allocator)
	defer harnesses_destroy(out[:])
	index := make(map[string]int, context.temp_allocator)
	add_presets(&out, &index, context.allocator)
	testing.expect_value(t, len(out), len(BUILTIN_PRESETS))

	cfg := `{"claude":{"bin":"claude-next","argv":["-p","{prompt}"],"timeout_sec":30},"fake":{"bin":"echo","argv":["{prompt}"],"output":"json","name":"Fake Echo"}}`
	err := merge_json(&out, &index, cfg, .Config, "test", context.allocator)
	testing.expect(t, len(err) == 0)

	cl, ok := harness_find(out[:], "claude")
	testing.expect(t, ok)
	testing.expect_value(t, cl.bin, "claude-next")
	testing.expect_value(t, cl.timeout_sec, 30)
	testing.expect_value(t, cl.source, Source.Config)
	testing.expect_value(t, len(cl.argv), 2)

	fk, f_ok := harness_find(out[:], "fake")
	testing.expect(t, f_ok)
	testing.expect_value(t, fk.output, Output_Mode.Json)
	testing.expect_value(t, fk.name, "Fake Echo")

	// untouched builtins survive the merge
	gm, g_ok := harness_find(out[:], "gemini")
	testing.expect(t, g_ok)
	testing.expect_value(t, gm.source, Source.Builtin)
}

@(test)
test_config_bad_json :: proc(t: ^testing.T) {
	out := make([dynamic]Harness, context.allocator)
	defer harnesses_destroy(out[:])
	index := make(map[string]int, context.temp_allocator)
	err := merge_json(&out, &index, "{not json", .Config, "test", context.allocator)
	testing.expect(t, len(err) > 0)
	delete(err, context.temp_allocator)
	// non-object top level is an error too
	err2 := merge_json(&out, &index, "[1,2]", .Config, "test", context.allocator)
	testing.expect(t, len(err2) > 0)
	delete(err2, context.temp_allocator)
}

@(test)
test_detect_abs_and_path :: proc(t: ^testing.T) {
	list := make([dynamic]Harness, context.allocator)
	defer harnesses_destroy(list[:])
	test_append(&list, "echoer", "/bin/echo", nil)
	test_append(&list, "missing", "nullray-definitely-no-such-bin", nil)
	detect(list[:], context.allocator)
	testing.expect(t, strings.has_suffix(list[0].binary, "echo"))
	testing.expect_value(t, list[1].binary, "")
}

@(test)
test_detect_path_lookup :: proc(t: ^testing.T) {
	when ODIN_OS == .Windows {
		return
	}
	list := make([dynamic]Harness, context.allocator)
	defer harnesses_destroy(list[:])
	test_append(&list, "sh", "sh", nil)
	detect(list[:], context.allocator)
	testing.expect(t, len(list[0].binary) > 0)
}

@(test)
test_run_echo_argv_single :: proc(t: ^testing.T) {
	when ODIN_OS == .Windows {
		return
	}
	dir := "/tmp/nullray-harness-test"
	_ = os.remove_all(dir)
	_ = os.make_directory_all(dir)
	defer os.remove_all(dir)
	script, jerr := filepath.join({dir, "args.sh"}, context.temp_allocator)
	testing.expect(t, jerr == nil)
	body := "#!/bin/sh\ni=0\nfor a in \"$@\"; do i=$((i+1)); echo \"arg$i=$a\"; done\n"
	testing.expect(t, os.write_entire_file(script, body) == nil)

	list := make([dynamic]Harness, context.allocator)
	defer harnesses_destroy(list[:])
	test_append(&list, "fake", "sh", []string{script, "{prompt}", "{cwd}"})
	list[0].timeout_sec = 10
	detect(list[:], context.allocator)

	prompt := "two words with   spaces"
	out, err := run_defined(list[:], "fake", prompt, dir, 0, context.allocator)
	testing.expect(t, len(err) == 0, err)
	defer delete(out)
	// The prompt must arrive as ONE argv element (arg1) and cwd as arg2.
	testing.expect(t, strings.contains(out, "arg1=two words with   spaces"), out)
	testing.expect(t, strings.contains(out, "arg2="), out)
	testing.expect(t, !strings.contains(out, "arg3="), out)
}

@(test)
test_run_timeout :: proc(t: ^testing.T) {
	when ODIN_OS == .Windows {
		return
	}
	list := make([dynamic]Harness, context.allocator)
	defer harnesses_destroy(list[:])
	test_append(&list, "sleeper", "sleep", []string{"30"})
	list[0].timeout_sec = 1
	detect(list[:], context.allocator)
	out, err := run_defined(list[:], "sleeper", "hi", "/tmp", 1, context.allocator)
	testing.expect(t, len(err) == 0, err)
	defer delete(out)
	testing.expect(t, strings.contains(out, "timeout"), out)
}

// Regression: a detached grandchild holding the pipe write end must not
// wedge the post-exit drain, and the real exit code must survive.
@(test)
test_exec_capture_detached_grandchild :: proc(t: ^testing.T) {
	when ODIN_OS == .Windows {
		return
	}
	start := time.now()
	stdout, stderr, code, timed, err := exec_capture(
		[]string{"/bin/sh", "-c", "sleep 15 & exit 7"},
		"/tmp",
		10,
		nil,
		nil,
		context.allocator,
	)
	defer delete(stdout)
	defer delete(stderr)
	if len(err) > 0 {
		defer delete(err)
	}
	testing.expectf(t, len(err) == 0, "err=%q", err)
	testing.expectf(t, code == 7 && !timed, "code=%d timed=%v", code, timed)
	testing.expectf(t, time.since(start) < 8 * time.Second, "detached grandchild wedged the drain")
}

// Regression: a flooding writer kept drain_cap inside its has_data loop so
// the timeout check never ran.
@(test)
test_exec_capture_flood_timeout :: proc(t: ^testing.T) {
	when ODIN_OS == .Windows {
		return
	}
	start := time.now()
	stdout, stderr, _, timed, err := exec_capture(
		[]string{"/bin/sh", "-c", "while :; do echo flood; done"},
		"/tmp",
		1,
		nil,
		nil,
		context.allocator,
	)
	defer delete(stdout)
	defer delete(stderr)
	if len(err) > 0 {
		defer delete(err)
	}
	testing.expect(t, timed)
	testing.expectf(t, time.since(start) < 8 * time.Second, "flood wedged the drain")
}

@(test)
test_run_bad_id_and_missing_binary :: proc(t: ^testing.T) {
	list := make([dynamic]Harness, context.allocator)
	defer harnesses_destroy(list[:])
	test_append(&list, "ghost", "nullray-no-such-bin-xyz", []string{"{prompt}"})
	_, err := run_defined(list[:], "nope", "hi", "/tmp", 0, context.allocator)
	testing.expect(t, strings.contains(err, "unknown harness"), err)
	delete(err)
	_, err2 := run_defined(list[:], "ghost", "hi", "/tmp", 0, context.allocator)
	testing.expect(t, strings.contains(err2, "not found"), err2)
	delete(err2)
}

@(test)
test_run_disabled_env :: proc(t: ^testing.T) {
	had, prev := test_env_set(constants.ENV_HARNESS, "0")
	defer test_env_restore(constants.ENV_HARNESS, had, prev)
	list := make([dynamic]Harness, context.allocator)
	defer harnesses_destroy(list[:])
	_, err := run_defined(list[:], "claude", "hi", "/tmp", 0, context.allocator)
	testing.expect(t, strings.contains(err, "disabled"), err)
	delete(err)
	testing.expect(t, !harness_enabled())
}

@(test)
test_extract_json_result :: proc(t: ^testing.T) {
	got := extract_json_result(`{"result":"hello json"}`, context.allocator)
	defer delete(got)
	testing.expect_value(t, got, "hello json")

	body := "noise line\n{\"type\":\"end\",\"output\":\"last one\"}\n"
	got2 := extract_json_result(body, context.allocator)
	defer delete(got2)
	testing.expect_value(t, got2, "last one")

	got3 := extract_json_result("plain text\nnothing json", context.allocator)
	testing.expect_value(t, got3, "")
}

@(test)
test_load_merges_config_dir :: proc(t: ^testing.T) {
	base := "/tmp/nullray-harness-xdg"
	_ = os.remove_all(base)
	defer os.remove_all(base)
	cfg_dir, _ := filepath.join({base, constants.CONFIG_DIR_NAME}, context.temp_allocator)
	_ = os.make_directory_all(cfg_dir)
	cfg_path, _ := filepath.join({cfg_dir, constants.HARNESSES_FILE}, context.temp_allocator)
	data := `{"fake":{"bin":"echo","argv":["{prompt}"],"timeout_sec":5}}`
	testing.expect(t, os.write_entire_file(cfg_path, data) == nil)

	had, prev := test_env_set("XDG_CONFIG_HOME", base)
	defer test_env_restore("XDG_CONFIG_HOME", had, prev)

	list := load_harnesses()
	defer harnesses_destroy(list)
	fk, ok := harness_find(list, "fake")
	testing.expect(t, ok)
	testing.expect_value(t, fk.bin, "echo")
	testing.expect_value(t, fk.timeout_sec, 5)
	testing.expect_value(t, fk.source, Source.Config)
	_, ok2 := harness_find(list, "claude")
	testing.expect(t, ok2)
}
