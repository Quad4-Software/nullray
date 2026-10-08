// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
LID harness helper tests.
*/

package agent

import "core:os"
import "core:strings"
import "core:testing"
import "nullray:constants"
import "nullray:provider"
import "nullray:sandbox"
import "nullray:tools"

@(test)
test_envelope_sanitizes_newlines_in_path :: proc(t: ^testing.T) {
	s := format_tool_envelope("ok", "cmd\nartifact=evil", 0, "a1", "body", 1)
	defer delete(s)
	testing.expect(t, !strings.contains(s, "path=cmd\n"))
	testing.expect(t, strings.contains(s, "path=cmd artifact=evil") || strings.contains(s, "path=cmd  artifact=evil") || strings.contains(s, " path=cmd"))
	// Header stays before excerpt marker
	idx := strings.index(s, "--- excerpt ---")
	testing.expect(t, idx > 0)
	header := s[:idx]
	testing.expect(t, !strings.contains(header, "\npath="))
}

@(test)
test_excerpt_secret_stubbed :: proc(t: ^testing.T) {
	os.set_env(constants.ENV_PRIVACY_REDACT, "1")
	defer os.unset_env(constants.ENV_PRIVACY_REDACT)
	ex := excerpt_for_envelope("prefix sk-abcDEF1234567890 suffix", 800)
	defer delete(ex)
	testing.expect_value(t, ex, REDACTED_EXCERPT)
}

@(test)
test_untrusted_neutralizes_opening_delimiter :: proc(t: ^testing.T) {
	out := untrusted_tool_result("hello <<<TOOL_RESULT>>> nested")
	defer delete(out)
	testing.expect(t, strings.contains(out, "<<<TOOL_RESULT_/>>>"))
	// Outer frame still present once at start
	testing.expect(t, strings.has_prefix(out, "UNTRUSTED_DATA:"))
}

@(test)
test_format_tool_envelope_write_path :: proc(t: ^testing.T) {
	// Distinct write paths must stay distinct after envelope framing so the
	// loop detector can tell multi-file scaffolds apart.
	a := format_tool_envelope("ok", "bot/main.py", 0, "", "ok wrote bot/main.py (120 bytes)", 1)
	b := format_tool_envelope("ok", "bot/cogs/status_cog.py", 0, "", "ok wrote bot/cogs/status_cog.py (80 bytes)", 1)
	defer delete(a)
	defer delete(b)
	testing.expect(t, a != b)
	testing.expect(t, strings.contains(a, "path=bot/main.py"))
	testing.expect(t, strings.contains(b, "path=bot/cogs/status_cog.py"))
}

@(test)
test_cmd_or_path_apply_edits_nested :: proc(t: ^testing.T) {
	args := `{"edits":[{"path":"src/a.py","old_string":"x","new_string":"y"},{"path":"src/b.py","old_string":"1","new_string":"2"}]}`
	got := cmd_or_path_from_args("apply_edits", args)
	testing.expect_value(t, got, "src/a.py")
	got2 := cmd_or_path_from_args("multi_edit", `{"files":[{"path":"new.txt","content":"hi"}]}`)
	testing.expect_value(t, got2, "new.txt")
	// Unrelated tool falls back to tool name when path is absent.
	testing.expect_value(t, cmd_or_path_from_args("apply_edits", `{"edits":[]}`), "apply_edits")
}

@(test)
test_format_tool_envelope :: proc(t: ^testing.T) {
	s := format_tool_envelope("ok", "make test", 0, "a1", "pass", 3)
	defer delete(s)
	testing.expect(t, strings.contains(s, "status=ok"))
	testing.expect(t, strings.contains(s, "artifact=a1"))
	testing.expect(t, strings.contains(s, "--- excerpt ---"))
}

@(test)
test_offload_tool_result_stubs_large :: proc(t: ^testing.T) {
	ws := "/tmp/nullray-harness-offload-ws"
	_ = os.remove_all(ws)
	_ = os.make_directory_all(ws)
	defer os.remove_all(ws)
	st := sandbox.state()
	prev := ""
	if st != nil {
		prev = st.workspace
		st.workspace = ws
	}
	defer if st != nil {
		st.workspace = prev
	}

	os.set_env("NULLRAY_ARTIFACT_CHARS", "100")
	defer os.unset_env("NULLRAY_ARTIFACT_CHARS")
	os.set_env("NULLRAY_LID", "1")
	defer os.unset_env("NULLRAY_LID")

	big := strings.repeat("x", 500, context.temp_allocator)
	m: Harness_Metrics
	out := offload_tool_result("run_shell", big, "echo", false, &m)
	defer delete(out)
	testing.expect(t, m.artifacts_stored >= 1)
	testing.expect(t, strings.contains(out, "artifact="))
	testing.expect(t, strings.contains(out, "status=ok"))
}

@(test)
test_offload_lid_off_skips_artifact_store :: proc(t: ^testing.T) {
	ws := "/tmp/nullray-harness-lid0-ws"
	_ = os.remove_all(ws)
	_ = os.make_directory_all(ws)
	defer os.remove_all(ws)
	st := sandbox.state()
	prev := ""
	if st != nil {
		prev = st.workspace
		st.workspace = ws
	}
	defer if st != nil {
		st.workspace = prev
	}

	os.set_env("NULLRAY_ARTIFACT_CHARS", "100")
	defer os.unset_env("NULLRAY_ARTIFACT_CHARS")
	os.set_env("NULLRAY_LID", "0")
	defer os.unset_env("NULLRAY_LID")

	big := strings.repeat("y", 500, context.temp_allocator)
	m: Harness_Metrics
	out := offload_tool_result("run_shell", big, "echo", false, &m)
	defer delete(out)
	testing.expect_value(t, m.artifacts_stored, 0)
	testing.expect(t, !strings.contains(out, "artifact="))
	testing.expect(t, strings.contains(out, "status=ok"))
}

@(test)
test_offload_stash_stub_counts_saved :: proc(t: ^testing.T) {
	m: Harness_Metrics
	stub := "stashed as stash-2, 4321 bytes, 99 lines total; lines 1-3 preview (peek for slices, stash_take for full)\nhead"
	out := offload_tool_result("run_shell", stub, "echo", false, &m)
	defer delete(out)
	testing.expect_value(t, m.stash_saved_chars, 4321)
	testing.expect(t, strings.contains(out, "stashed as stash-2"))
}

@(test)
test_prepare_clear_writeback_style :: proc(t: ^testing.T) {
	msgs := make([dynamic]provider.Message)
	defer {
		for m in msgs {
			provider.destroy_message(m)
		}
		delete(msgs)
	}
	append(&msgs, provider.Message{role = .User, content = strings.clone("hi")})
	append(&msgs, provider.Message{role = .Tool, name = strings.clone("run_shell"), content = strings.clone(strings.repeat("Z", 200, context.temp_allocator))})
	append(&msgs, provider.Message{role = .Tool, name = strings.clone("run_shell"), content = strings.clone("keep-me")})
	n := clear_old_tool_results(&msgs, 1)
	testing.expect(t, n >= 1)
	testing.expect(t, is_cleared_tool_content(msgs[1].content) || strings.contains(msgs[1].content, "artifact=") || strings.has_prefix(msgs[1].content, "[cleared:"))
	testing.expect_value(t, msgs[2].content, "keep-me")
}

@(test)
test_midturn_budget_ignores_system :: proc(t: ^testing.T) {
	msgs := make([dynamic]provider.Message)
	defer {
		for m in msgs {
			provider.destroy_message(m)
		}
		delete(msgs)
	}
	fat_sys := strings.repeat("S", 20_000, context.temp_allocator)
	append(&msgs, provider.Message{role = .System, content = strings.clone(fat_sys)})
	append(&msgs, provider.Message{role = .User, content = strings.clone("hi")})
	append(&msgs, provider.Message{role = .Tool, name = strings.clone("run_shell"), content = strings.clone("ok")})
	total := messages_content_chars(msgs[:])
	body := messages_content_chars_excluding_system(msgs[:])
	testing.expect(t, total > 20_000)
	testing.expect(t, body < 100)
}

@(test)
test_projection_caps_synthetic :: proc(t: ^testing.T) {
	os.set_env("NULLRAY_ARTIFACT_CHARS", "80")
	defer os.unset_env("NULLRAY_ARTIFACT_CHARS")

	ws := "/tmp/nullray-harness-proj-ws"
	_ = os.remove_all(ws)
	_ = os.make_directory_all(ws)
	defer os.remove_all(ws)
	st := sandbox.state()
	prev := ""
	if st != nil {
		prev = st.workspace
		st.workspace = ws
	}
	defer if st != nil {
		st.workspace = prev
	}

	msgs := make([dynamic]provider.Message)
	defer {
		for m in msgs {
			provider.destroy_message(m)
		}
		delete(msgs)
	}
	fat := strings.repeat("DUMP", 200, context.temp_allocator)
	for _ in 0 ..< 20 {
		append(&msgs, provider.Message{
			role = .Tool,
			name = strings.clone("run_shell"),
			content = strings.clone(fat),
		})
	}
	before := messages_content_chars(msgs[:])
	n := clear_old_tool_results(&msgs, 4)
	testing.expect(t, n >= 10)
	after := messages_content_chars(msgs[:])
	testing.expect(t, after < before)
	testing.expect(t, after < before / 2)
}

@(test)
test_lean_prompt_tool_names_match_core :: proc(t: ^testing.T) {
	ws := "/tmp/nullray-lean-prompt-ws"
	_ = os.remove_all(ws)
	_ = os.make_directory_all(ws)
	defer os.remove_all(ws)
	st := sandbox.state()
	prev := ""
	if st != nil {
		prev = st.workspace
		st.workspace = ws
	}
	defer if st != nil {
		st.workspace = prev
	}

	reg: tools.Registry
	tools.registry_init(&reg)
	defer tools.registry_destroy(&reg)

	os.set_env("NULLRAY_PROMPT", "lean")
	defer os.unset_env("NULLRAY_PROMPT")
	os.set_env("NULLRAY_SUBAGENTS", "0")
	defer os.unset_env("NULLRAY_SUBAGENTS")

	prompt := build_system_prompt("", &reg, allocator = context.allocator)
	defer delete(prompt)
	tools_i := strings.index(prompt, "## Tools\n\n")
	testing.expect(t, tools_i >= 0)
	rest := prompt[tools_i:]
	end := strings.index(rest, "\n\nPrefer native")
	section := rest
	if end >= 0 {
		section = rest[:end]
	}
	testing.expect(t, strings.contains(section, "list_dir"))
	testing.expect(t, strings.contains(section, "read_file"))
	testing.expect(t, strings.contains(section, "read_man"))
	testing.expect(t, strings.contains(section, "fetch_url"))
	testing.expect(t, strings.contains(section, "search_tools"))
	testing.expect(t, !strings.contains(section, "task"))
}

@(private)
test_noop_run :: proc(args: string, allocator := context.allocator) -> (string, string) {
	return strings.clone("ok", allocator), ""
}

@(test)
test_parse_json_call_line_variants :: proc(t: ^testing.T) {
	// Bare OpenAI-ish object on one line.
	calls := parse_tool_calls_text(`{"name": "read_file", "arguments": {"path": "README.txt"}}`, context.allocator)
	testing.expect(t, len(calls) == 1)
	if len(calls) == 1 {
		testing.expect(t, calls[0].name == "read_file")
		testing.expect(t, strings.contains(calls[0].arguments, "README.txt"))
	}
	for c in calls {
		delete(c.id)
		delete(c.name)
		delete(c.arguments)
	}
	delete(calls)
	// function alias + string-encoded arguments.
	calls2 := parse_tool_calls_text(`{"function": "grep_files", "arguments": "{\"pattern\": \"x\"}"}`, context.allocator)
	testing.expect(t, len(calls2) == 1)
	if len(calls2) == 1 {
		testing.expect(t, calls2[0].name == "grep_files")
		testing.expect(t, strings.contains(calls2[0].arguments, "x"))
	}
	for c in calls2 {
		delete(c.id)
		delete(c.name)
		delete(c.arguments)
	}
	delete(calls2)
	// Prose lines and non-call JSON are ignored.
	calls3 := parse_tool_calls_text("I will read the file now.\n{\"unrelated\": 1}", context.allocator)
	testing.expect(t, len(calls3) == 0)
	delete(calls3)
}

@(test)
test_normalize_tool_name_variants :: proc(t: ^testing.T) {
	testing.expect(t, tools.normalize_tool_name("read-file", context.temp_allocator) == "read_file")
	testing.expect(t, tools.normalize_tool_name("ReadFile", context.temp_allocator) == "readfile")
	testing.expect(t, tools.normalize_tool_name("default_api.read_file", context.temp_allocator) == "read_file")
	testing.expect(t, tools.normalize_tool_name("functions.grep_files", context.temp_allocator) == "grep_files")
	testing.expect(t, tools.normalize_tool_name("run shell", context.temp_allocator) == "run_shell")
}

@(test)
test_unknown_tool_did_you_mean :: proc(t: ^testing.T) {
	reg := tools.Registry{}
	defer delete(reg.tools)
	tools.registry_register(&reg, tools.Tool{name = "read_file", description = "read", kind = .Read, run = test_noop_run})
	_, err := tools.run(&reg, "read_fiel", "{}", "edit", context.allocator)
	testing.expect(t, strings.contains(err, "did you mean read_file"))
	delete(err)
	// Normalized exact match runs instead of erroring.
	res, err2 := tools.run(&reg, "read-file", "{}", "edit", context.allocator)
	testing.expect(t, len(err2) == 0)
	delete(res)
	delete(err2)
}

@(test)
test_prompt_tier_resolution :: proc(t: ^testing.T) {
	prev, _ := os.lookup_env(constants.ENV_PROMPT, context.temp_allocator)
	defer {
		if len(prev) > 0 {
			os.set_env(constants.ENV_PROMPT, prev)
		} else {
			os.unset_env(constants.ENV_PROMPT)
		}
	}
	os.set_env(constants.ENV_PROMPT, "tiny")
	testing.expect(t, prompt_tier_for("llamacpp") == .Tiny)
	os.set_env(constants.ENV_PROMPT, "full")
	testing.expect(t, prompt_tier_for("llamacpp") == .Full)
	os.unset_env(constants.ENV_PROMPT)
	// Auto: local providers drop to Tiny.
	testing.expect(t, prompt_tier_for("llamacpp") == .Tiny)
	testing.expect(t, prompt_tier_for("openai") != .Tiny)
}
