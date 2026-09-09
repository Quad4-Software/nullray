// SPDX-License-Identifier: 0BSD
/*
Tests for repo_map shallow tree tool.
*/

package tools

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"
import "nullray:sandbox"

@(test)
test_repo_map_depth_and_skip :: proc(t: ^testing.T) {
	root := "/tmp/nullray-repo-map"
	_ = os.remove_all(root)
	testing.expect(t, os.make_directory_all(root) == nil)
	defer os.remove_all(root)

	sub, j1 := filepath.join({root, "src"}, context.temp_allocator)
	testing.expect(t, j1 == nil)
	testing.expect(t, os.make_directory_all(sub) == nil)
	git, j2 := filepath.join({root, ".git", "objects"}, context.temp_allocator)
	testing.expect(t, j2 == nil)
	testing.expect(t, os.make_directory_all(git) == nil)
	file, j3 := filepath.join({sub, "main.odin"}, context.temp_allocator)
	testing.expect(t, j3 == nil)
	testing.expect(t, os.write_entire_file(file, transmute([]byte)string("package main\n")) == nil)

	prev := sandbox.workspace_current()
	sandbox.workspace_override_set(root)
	defer {
		if len(prev) > 0 {
			sandbox.workspace_override_set(prev)
		} else {
			sandbox.workspace_override_clear()
		}
	}

	out, err := tool_repo_map(`{"path":".","depth":"2"}`, context.allocator)
	defer delete(out)
	testing.expect(t, err == "")
	testing.expect(t, strings.contains(out, "src/"))
	testing.expect(t, strings.contains(out, "main.odin"))
	testing.expect(t, !strings.contains(out, ".git"))
	testing.expect(t, !strings.contains(out, "objects"))
}

@(test)
test_repo_map_secret_path_denied :: proc(t: ^testing.T) {
	root := "/tmp/nullray-repo-map-ws"
	_ = os.remove_all(root)
	testing.expect(t, os.make_directory_all(root) == nil)
	defer os.remove_all(root)

	prev := sandbox.workspace_current()
	sandbox.workspace_override_set(root)
	defer {
		if len(prev) > 0 {
			sandbox.workspace_override_set(prev)
		} else {
			sandbox.workspace_override_clear()
		}
	}

	out, err := tool_repo_map(`{"path":".env"}`, context.allocator)
	defer delete(out)
	testing.expect(t, len(err) > 0)
	if len(err) > 0 {
		delete(err)
	}
}
