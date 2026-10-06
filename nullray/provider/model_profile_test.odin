// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package provider

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"
import "core:time"
import "nullray:constants"

@(private)
profiles_free :: proc(profiles: []Model_Profile) {
	for p in profiles {
		delete(p.match)
	}
	delete(profiles)
}

@(test)
test_profile_parse_fixture :: proc(t: ^testing.T) {
	text := `{"profiles":[
		{"match":"qwen*","num_ctx":32768,"temperature":0.6,"reasoning":"off",
		 "one_tool_per_turn":true,"prompt_tier":"lean"},
		{"match":"gpt-oss:*","ctx":131072,"top_p":0.9,"parallel_tool_calls":false}
	]}`
	profiles := profile_parse(text, context.allocator)
	defer profiles_free(profiles)
	testing.expect_value(t, len(profiles), 2)

	p0 := profiles[0]
	testing.expect(t, p0.match == "qwen*")
	testing.expect_value(t, p0.num_ctx, 32768)
	testing.expect(t, p0.temperature_set && abs(p0.temperature - 0.6) < 0.001)
	testing.expect(t, !p0.top_p_set)
	testing.expect(t, p0.reasoning == .Off)
	testing.expect(t, p0.one_tool_per_turn)
	testing.expect(t, p0.prompt_tier == .Lean)

	p1 := profiles[1]
	testing.expect_value(t, p1.ctx, 131072)
	testing.expect(t, p1.top_p_set && abs(p1.top_p - 0.9) < 0.001)
	testing.expect(t, p1.parallel_tool_calls_set && !p1.parallel_tool_calls)
	testing.expect(t, p1.prompt_tier == .Unset)
	testing.expect(t, p1.reasoning == .Unset)
}

@(test)
test_profile_glob_match :: proc(t: ^testing.T) {
	testing.expect(t, profile_glob_match("qwen*", "qwen3:8b"))
	testing.expect(t, profile_glob_match("gpt-oss:*", "gpt-oss:20b"))
	testing.expect(t, !profile_glob_match("qwen*", "llama3"))
	// * crosses separators so provider/model ids stay matchable.
	testing.expect(t, profile_glob_match("*", "openai/gpt-5"))
	testing.expect(t, profile_glob_match("openai/*", "openai/gpt-5"))
	testing.expect(t, profile_glob_match("QWEN*", "qwen3"))
	testing.expect(t, profile_glob_match("qwen?", "qwen3"))
	testing.expect(t, !profile_glob_match("qwen?", "qwen33"))
	testing.expect(t, !profile_glob_match("", "qwen3"))
}

@(test)
test_profile_for_first_match_wins :: proc(t: ^testing.T) {
	profile_install_for_test(`{"profiles":[
		{"match":"qwen3*","num_ctx":8192},
		{"match":"qwen*","num_ctx":32768}
	]}`)
	defer profile_reset_for_test()
	p, ok := profile_for("qwen3:8b")
	testing.expect(t, ok)
	testing.expect_value(t, p.num_ctx, 8192)
	_, miss := profile_for("mistral")
	testing.expect(t, !miss)
}

@(test)
test_profile_apply_request :: proc(t: ^testing.T) {
	profile_install_for_test(`{"profiles":[{"match":"qwen*","temperature":0.6,
		"top_p":0.9,"reasoning":"off","parallel_tool_calls":false}]}`)
	defer profile_reset_for_test()

	req := Chat_Request{}
	profile_apply("ollama", "qwen3:8b", &req)
	testing.expect(t, req.temperature_set && abs(req.temperature - 0.6) < 0.001)
	testing.expect(t, req.top_p_set && abs(req.top_p - 0.9) < 0.001)
	testing.expect(t, req.parallel_tool_calls_set && !req.parallel_tool_calls)
	testing.expect(t, req.reasoning_effort == "none")

	// Explicit request values win over the profile.
	req2 := Chat_Request{temperature = 0.2, temperature_set = true, reasoning_effort = "high"}
	profile_apply("ollama", "qwen3:8b", &req2)
	testing.expect(t, req2.temperature_set && abs(req2.temperature - 0.2) < 0.001)
	testing.expect(t, req2.reasoning_effort == "high")
	testing.expect(t, req2.top_p_set && abs(req2.top_p - 0.9) < 0.001)
}

@(test)
test_profile_body_wiring :: proc(t: ^testing.T) {
	saved, had := os.lookup_env(constants.ENV_OLLAMA_NUM_CTX, context.temp_allocator)
	defer if had {
		os.set_env(constants.ENV_OLLAMA_NUM_CTX, saved)
	} else {
		os.unset_env(constants.ENV_OLLAMA_NUM_CTX)
	}
	os.unset_env(constants.ENV_OLLAMA_NUM_CTX)

	profile_install_for_test(`{"profiles":[{"match":"qwen*","temperature":0.6,
		"num_ctx":32768,"parallel_tool_calls":false}]}`)
	defer profile_reset_for_test()

	p := Provider{id = "ollama", base_url = "http://127.0.0.1:1"}
	req := Chat_Request{
		messages = []Message{{role = .User, content = "hi"}},
		tools_json = `[{"type":"function","function":{"name":"x","parameters":{"type":"object"}}}]`,
	}
	body := build_openai_chat_body(&p, req, "qwen3:8b", false, nil)
	testing.expect(t, strings.contains(body, `"temperature":0.6`))
	testing.expect(t, strings.contains(body, `"num_ctx":32768`))
	testing.expect(t, strings.contains(body, `"parallel_tool_calls":false`))

	// Env wins over the profile num_ctx.
	os.set_env(constants.ENV_OLLAMA_NUM_CTX, "48000")
	body2 := build_openai_chat_body(&p, req, "qwen3:8b", false, nil)
	testing.expect(t, strings.contains(body2, `"num_ctx":48000`))
}

@(test)
test_profile_serialize_round_trip :: proc(t: ^testing.T) {
	text := `{"profiles":[{"match":"qwen*","num_ctx":32768,"temperature":0.6,
		"reasoning":"on","one_tool_per_turn":true,"prompt_tier":"tiny",
		"parallel_tool_calls":true}]}`
	profiles := profile_parse(text, context.allocator)
	defer profiles_free(profiles)
	out := profile_serialize(profiles, context.allocator)
	defer delete(out)
	again := profile_parse(out, context.allocator)
	defer profiles_free(again)
	testing.expect_value(t, len(again), 1)
	if len(again) == 0 {
		return
	}
	p := again[0]
	testing.expect(t, p.match == "qwen*")
	testing.expect_value(t, p.num_ctx, 32768)
	testing.expect(t, p.temperature_set && abs(p.temperature - 0.6) < 0.001)
	testing.expect(t, p.reasoning == .On)
	testing.expect(t, p.one_tool_per_turn)
	testing.expect(t, p.prompt_tier == .Tiny)
	testing.expect(t, p.parallel_tool_calls_set && p.parallel_tool_calls)
}

@(test)
test_profile_workspace_trust_gate :: proc(t: ^testing.T) {
	base := fmt.tprintf("/tmp/nullray-prof-trust-%d", os.get_pid())
	cfg, _ := filepath.join({base, "cfg"}, context.temp_allocator)
	ws, _ := filepath.join({base, "ws", ".nullray"}, context.temp_allocator)
	defer os.remove_all(base)

	prev_xdg, had_xdg := os.lookup_env("XDG_CONFIG_HOME", context.allocator)
	defer if had_xdg {
		os.set_env("XDG_CONFIG_HOME", prev_xdg)
		delete(prev_xdg)
	} else {
		os.unset_env("XDG_CONFIG_HOME")
	}
	os.set_env("XDG_CONFIG_HOME", cfg)

	merr := os.make_directory_all(ws)
	testing.expect(t, merr == nil || merr == .Exist)
	path, _ := filepath.join({ws, "model_profiles.json"}, context.temp_allocator)
	body := `{"profiles":[{"match":"qwen*","temperature":0.9}]}`
	testing.expect(t, os.write_entire_file(path, transmute([]u8)body) == nil)

	// First sight of a workspace profile table is denied.
	testing.expect(t, !profile_path_trusted(path))

	// Write the approval record in the shared trust store format.
	info, serr := os.stat(path, context.temp_allocator)
	testing.expect(t, serr == nil)
	store, _ := filepath.join({cfg, "nullray", "hooks_trusted.json"}, context.temp_allocator)
	sdir := filepath.dir(store)
	derr := os.make_directory_all(sdir)
	testing.expect(t, derr == nil || derr == .Exist)
	// fmt treats { in the format string as a directive; build via concat.
	rec := strings.concatenate({
		`{"version":1,"files":{"`,
		path,
		`":{"mtime_ns":"`,
		fmt.tprintf("%d", time.to_unix_nanoseconds(info.modification_time)),
		`","size":"`,
		fmt.tprintf("%d", i64(info.size)),
		`"}}}`,
	}, context.temp_allocator)
	testing.expect(t, os.write_entire_file(store, transmute([]u8)rec) == nil)
	testing.expect(t, profile_path_trusted(path))

	// A rewrite invalidates the record.
	body2 := `{"profiles":[{"match":"qwen*","temperature":0.9,"num_ctx":4096}]}`
	testing.expect(t, os.write_entire_file(path, transmute([]u8)body2) == nil)
	testing.expect(t, !profile_path_trusted(path))
}
