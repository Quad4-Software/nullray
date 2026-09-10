// SPDX-License-Identifier: 0BSD
package vcs

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

@(test)
test_collect_review_diff_include_untracked :: proc(t: ^testing.T) {
	root := "/tmp/nullray-vcs-review-ut"
	_ = os.remove_all(root)
	testing.expect(t, os.make_directory_all(root) == nil)
	defer os.remove_all(root)

	repo := Repo{kind = .Git, root = root}
	out, err := run(repo, {"git", "init"}, context.temp_allocator)
	testing.expectf(t, err == "", "git init: %s %s", err, out)
	_, _ = run(repo, {"git", "config", "user.email", "t@t"}, context.temp_allocator)
	_, _ = run(repo, {"git", "config", "user.name", "t"}, context.temp_allocator)

	tracked, _ := filepath.join({root, "a.txt"}, context.temp_allocator)
	testing.expect(t, os.write_entire_file(tracked, transmute([]u8)string("one\n")) == nil)
	_, _ = run(repo, {"git", "add", "a.txt"}, context.temp_allocator)
	_, _ = run(repo, {"git", "commit", "-m", "init"}, context.temp_allocator)

	newbie, _ := filepath.join({root, "new.txt"}, context.temp_allocator)
	testing.expect(t, os.write_entire_file(newbie, transmute([]u8)string("fresh\n")) == nil)

	detected := detect(root)
	defer repo_destroy(&detected)
	testing.expect_value(t, detected.kind, Kind.Git)

	diff, label, derr := collect_review_diff(detected, Diff_Opts{scope = .Working, include_untracked = true})
	defer delete(diff)
	defer delete(label)
	testing.expectf(t, derr == "", "collect err: %s", derr)
	testing.expect(t, strings.contains(diff, "new.txt") || strings.contains(diff, "fresh"), diff)
	testing.expect(t, strings.contains(label, "untracked"), label)
}
