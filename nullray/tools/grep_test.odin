// SPDX-License-Identifier: 0BSD
/*
Tests for grep_files line-number output.
*/

package tools

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"
import "nullray:sandbox"

@(test)
test_grep_files_emits_line_numbers :: proc(t: ^testing.T) {
	root := "/tmp/nullray-grep-linenos"
	_ = os.remove_all(root)
	testing.expect(t, os.make_directory_all(root) == nil)
	defer os.remove_all(root)

	file, jerr := filepath.join({root, "sample.txt"}, context.temp_allocator)
	testing.expect(t, jerr == nil)
	testing.expect(t, os.write_entire_file(file, transmute([]byte)string("alpha\nbeta match here\ngamma\n")) == nil)

	prev := sandbox.workspace_current()
	sandbox.workspace_override_set(root)
	defer {
		if len(prev) > 0 {
			sandbox.workspace_override_set(prev)
		} else {
			sandbox.workspace_override_clear()
		}
	}

	out, err := tool_grep_files(`{"pattern":"match","path":"."}`, context.allocator)
	defer delete(out)
	testing.expect(t, err == "")
	testing.expect(t, strings.contains(out, "sample.txt:2:"))
	testing.expect(t, strings.contains(out, "match"))
}
