// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package experience

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"
import "core:time"
import "nullray:constants"
import "nullray:sandbox"

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
test_entry :: proc(task: string, tools: []string, outcome: string, allocator := context.temp_allocator) -> Exp_Entry {
	e: Exp_Entry
	e.task = task
	e.sig = exp_sig(task, allocator)
	e.outcome = outcome
	e.note = "note"
	e.ts = 1
	e.tools = make([dynamic]string, allocator)
	for name in tools {
		append(&e.tools, name)
	}
	return e
}

@(test)
test_entry_round_trip :: proc(t: ^testing.T) {
	e := test_entry("fix the flaky login test", []string{"read_file", "run_shell", "edit_file"}, "ok")
	e.note = "tests pass now \"quoted\""
	e.ts = 1700000000
	line := exp_format_entry(e, context.temp_allocator)
	got, ok := exp_parse_entry(line, context.temp_allocator)
	testing.expect(t, ok)
	defer {
		keep := make([dynamic]Exp_Entry, context.temp_allocator)
		append(&keep, got)
		exp_destroy_entries(&keep, context.temp_allocator)
	}
	testing.expect_value(t, got.task, e.task)
	testing.expect_value(t, got.sig, e.sig)
	testing.expect_value(t, got.outcome, "ok")
	testing.expect_value(t, got.note, e.note)
	testing.expect_value(t, got.ts, e.ts)
	testing.expect_value(t, len(got.tools), 3)
	testing.expect_value(t, got.tools[1], "run_shell")
}

@(test)
test_scoring_tool_prefix_first :: proc(t: ^testing.T) {
	_ = t
	entries := []Exp_Entry{
		test_entry("fix the login test", []string{"grep_files", "run_shell"}, "ok"),
		test_entry("fix the login test", []string{"read_file", "run_shell", "edit_file"}, "ok"),
	}
	seen := []string{"read_file", "run_shell"}
	hits := exp_top_k(entries, "login test", seen, 5, context.temp_allocator)
	testing.expect_value(t, len(hits), 2)
	testing.expect_value(t, hits[0], 1)
}

@(test)
test_top_k_cap :: proc(t: ^testing.T) {
	_ = t
	entries := make([dynamic]Exp_Entry, context.temp_allocator)
	for i in 0 ..< 8 {
		append(&entries, test_entry("same task", []string{"run_shell"}, "ok"))
	}
	hits := exp_top_k(entries[:], "same task", nil, EXP_RECALL_K, context.temp_allocator)
	testing.expect_value(t, len(hits), EXP_RECALL_K)
}

@(test)
test_stop_rule_on_looped_tail :: proc(t: ^testing.T) {
	_ = t
	entries := []Exp_Entry{
		test_entry("search forever", []string{"read_file", "grep_files", "grep_files", "grep_files"}, "looped"),
		test_entry("clean run", []string{"read_file", "edit_file"}, "ok"),
	}
	seen := []string{"run_shell", "grep_files", "grep_files"}
	lines := exp_stop_lines(entries, seen, 5, context.temp_allocator)
	testing.expect_value(t, len(lines), 1)
	if len(lines) > 0 {
		testing.expect(t, strings.has_prefix(lines[0], "stop: grep_files->grep_files"))
		delete(lines[0], context.temp_allocator)
	}
	delete(lines, context.temp_allocator)
	// A different tail produces no stop rule.
	lines2 := exp_stop_lines(entries, []string{"read_file", "edit_file"}, 5, context.temp_allocator)
	testing.expect_value(t, len(lines2), 0)
	delete(lines2, context.temp_allocator)
}

@(test)
test_distill_shape :: proc(t: ^testing.T) {
	base := fmt.tprintf("/tmp/nullray-exp-distill-%d", time.time_to_unix(time.now()))
	_ = os.remove_all(base)
	testing.expect(t, os.make_directory_all(base) == nil)
	defer os.remove_all(base)
	entries := []Exp_Entry{
		test_entry("fix login", []string{"read_file", "run_shell"}, "ok"),
		test_entry("fix login", []string{"read_file", "edit_file"}, "ok"),
		test_entry("search loop", []string{"grep_files", "grep_files"}, "looped"),
	}
	path, _ := filepath.join({base, "experience.md"}, context.temp_allocator)
	err := exp_distill_to(entries, path, context.temp_allocator)
	testing.expect_value(t, err, "")
	data, rerr := os.read_entire_file(path, context.temp_allocator)
	testing.expect(t, rerr == nil)
	body := string(data)
	testing.expect(t, strings.contains(body, "name: experience"))
	testing.expect(t, strings.contains(body, "- task \"fix login\" (2 runs, 0 failed)"))
	testing.expect(t, strings.contains(body, "- stop: "))
}

@(test)
test_disable_env :: proc(t: ^testing.T) {
	had, prev := test_env_set(constants.ENV_EXPERIENCE, "0")
	defer test_env_restore(constants.ENV_EXPERIENCE, had, prev)
	block := exp_prompt_block("anything", context.temp_allocator)
	testing.expect_value(t, block, "")
}

@(test)
test_untrusted_workspace_not_loaded :: proc(t: ^testing.T) {
	base := fmt.tprintf("/tmp/nullray-exp-trust-%d", time.time_to_unix(time.now()))
	_ = os.remove_all(base)
	ndir, _ := filepath.join({base, ".nullray"}, context.temp_allocator)
	testing.expect(t, os.make_directory_all(ndir) == nil)
	defer os.remove_all(base)

	st := sandbox.state()
	prev_ws := st.workspace
	st.workspace = base
	defer {
		st.workspace = prev_ws
	}

	// One entry under the workspace store.
	e := test_entry("repo task", []string{"run_shell"}, "ok")
	e.ts = 1
	line := exp_format_entry(e, context.temp_allocator)
	store_path, _ := filepath.join({ndir, "experience.jsonl"}, context.temp_allocator)
	testing.expect(t, os.write_entire_file(store_path, transmute([]u8)line) == nil)

	// A shipped hooks.json makes the workspace untrusted, so the store
	// resolves to the global fallback and the repo file stays unread.
	hooks_path, _ := filepath.join({ndir, "hooks.json"}, context.temp_allocator)
	testing.expect(t, os.write_entire_file(hooks_path, transmute([]u8)string(`{"Stop":["true"]}`)) == nil)
	entries := exp_load_entries(context.temp_allocator)
	testing.expect_value(t, len(entries), 0)
	exp_destroy_entries(&entries, context.temp_allocator)

	// With the gated file gone the workspace is trusted and entries load.
	testing.expect(t, os.remove(hooks_path) == nil)
	entries2 := exp_load_entries(context.temp_allocator)
	defer exp_destroy_entries(&entries2, context.temp_allocator)
	testing.expect_value(t, len(entries2), 1)
	if len(entries2) > 0 {
		testing.expect_value(t, entries2[0].task, "repo task")
	}
}
