// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package vcs

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"
import "nullray:constants"

@(test)
test_provenance_message_appends_trailers :: proc(t: ^testing.T) {
	msg := provenance_message("feat: add thing", "nullray", "qwen3.8", "opencode", context.temp_allocator)
	testing.expect(t, strings.contains(msg, "feat: add thing\n\nHarness: nullray"))
	testing.expect(t, strings.contains(msg, "Model: qwen3.8"))
	testing.expect(t, strings.contains(msg, "Method: opencode"))
}

@(test)
test_provenance_message_dedups :: proc(t: ^testing.T) {
	msg := provenance_message("fix\n\nHarness: nullray\nModel: x", "nullray", "y", "local", context.temp_allocator)
	testing.expect(t, !strings.contains(msg, "Model: y"))
}

@(test)
test_provenance_message_defaults :: proc(t: ^testing.T) {
	msg := provenance_message("work", "nullray", "", "", context.temp_allocator)
	testing.expect(t, strings.contains(msg, "Model: unknown"))
}

@(test)
test_json_escape_control :: proc(t: ^testing.T) {
	out := json_escape("a\"b\\c\n\x07", context.temp_allocator)
	testing.expect(t, strings.contains(out, "a\\\"b\\\\c\\n"))
	testing.expect(t, strings.contains(out, "\\u0007"))
}

@(test)
test_provenance_inactive_without_env :: proc(t: ^testing.T) {
	if _, had := os.lookup_env(constants.ENV_AI_PROVENANCE, context.temp_allocator); had {
		return
	}
	repo := Repo{kind = .Git}
	testing.expect(t, !provenance_active(repo))
	repo.kind = .Fossil
	testing.expect(t, !provenance_active(repo))
}

@(test)
test_provenance_commit_writes_trailers_and_note :: proc(t: ^testing.T) {
	if !os.exists("/usr/bin/git") {
		return
	}
	os.set_env(constants.ENV_AI_PROVENANCE, "1")
	defer os.unset_env(constants.ENV_AI_PROVENANCE)

	root := "/tmp/nullray-vcs-provenance-ut"
	_ = os.remove_all(root)
	testing.expect(t, os.make_directory_all(root) == nil)

	repo := Repo{kind = .Git, root = root}
	out, err := run(repo, {"git", "init"}, context.temp_allocator)
	testing.expectf(t, err == "", "git init: %s %s", err, out)
	_, _ = run(repo, {"git", "config", "user.email", "t@t"}, context.temp_allocator)
	_, _ = run(repo, {"git", "config", "user.name", "t"}, context.temp_allocator)
	_, _ = run(repo, {"git", "config", "commit.gpgsign", "false"}, context.temp_allocator)
	// Neutralize machine-level ai.* overrides so the test asserts live values.
	_, _ = run(repo, {"git", "config", "ai.harness", "nullray"}, context.temp_allocator)
	_, _ = run(repo, {"git", "config", "ai.model", "deepseek-v4.1-flash"}, context.temp_allocator)
	_, _ = run(repo, {"git", "config", "ai.method", "opencode"}, context.temp_allocator)

	tracked, _ := filepath.join({root, "a.txt"}, context.temp_allocator)
	testing.expect(t, os.write_entire_file(tracked, transmute([]u8)string("one\n")) == nil)
	_, _ = run(repo, {"git", "add", "a.txt"}, context.temp_allocator)

	out, err = commit(repo, "feat: test", "deepseek-v4.1-flash", "opencode", context.temp_allocator)
	testing.expectf(t, err == "", "commit: %s %s", err, out)

	log, lerr := run(repo, {"git", "log", "-1", "--format=%B"}, context.temp_allocator)
	testing.expect(t, lerr == "")
	testing.expect(t, strings.contains(log, "Harness: nullray"))
	testing.expect(t, strings.contains(log, "Model: deepseek-v4.1-flash"))
	testing.expect(t, strings.contains(log, "Method: opencode"))

	note, nerr := run(
		repo,
		{"git", "notes", "--ref=ai-provenance", "show", "HEAD"},
		context.temp_allocator,
	)
	testing.expectf(t, nerr == "", "note: %s", nerr)
	testing.expect(t, strings.contains(note, "\"model\":\"deepseek-v4.1-flash\""))
	testing.expect(t, strings.contains(note, "\"harness\":\"nullray\""))
}
