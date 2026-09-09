// SPDX-License-Identifier: 0BSD
package tools

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"
import "nullray:sandbox"

@(test)
test_grep_case_insensitive_builtin :: proc(t: ^testing.T) {
	root := "/tmp/nullray-grep-case"
	_ = os.remove_all(root)
	testing.expect(t, os.make_directory_all(root) == nil)
	defer os.remove_all(root)

	file, jerr := filepath.join({root, "sample.txt"}, context.temp_allocator)
	testing.expect(t, jerr == nil)
	testing.expect(t, os.write_entire_file(file, transmute([]byte)string("Alpha\nBETA match\ngamma\n")) == nil)

	prev := sandbox.workspace_current()
	sandbox.workspace_override_set(root)
	defer {
		if len(prev) > 0 {
			sandbox.workspace_override_set(prev)
		} else {
			sandbox.workspace_override_clear()
		}
	}

	out, err := tool_grep_files(`{"pattern":"beta","path":".","case_insensitive":"true","engine":"builtin"}`, context.allocator)
	defer delete(out)
	testing.expect(t, err == "")
	testing.expect(t, strings.contains(out, "sample.txt:2:"))
	testing.expect(t, strings.contains(out, "BETA"))
}

@(test)
test_grep_regex_builtin :: proc(t: ^testing.T) {
	root := "/tmp/nullray-grep-re"
	_ = os.remove_all(root)
	testing.expect(t, os.make_directory_all(root) == nil)
	defer os.remove_all(root)

	file, jerr := filepath.join({root, "re.txt"}, context.temp_allocator)
	testing.expect(t, jerr == nil)
	testing.expect(t, os.write_entire_file(file, transmute([]byte)string("foo123\nbar\nfoo9\n")) == nil)

	prev := sandbox.workspace_current()
	sandbox.workspace_override_set(root)
	defer {
		if len(prev) > 0 {
			sandbox.workspace_override_set(prev)
		} else {
			sandbox.workspace_override_clear()
		}
	}

	out, err := tool_grep_files(`{"pattern":"foo[0-9]+","path":".","regex":"true","engine":"builtin"}`, context.allocator)
	defer delete(out)
	testing.expect(t, err == "")
	testing.expect(t, strings.contains(out, "foo123"))
	testing.expect(t, strings.contains(out, "foo9"))
	testing.expect(t, !strings.contains(out, "bar"))
}

@(test)
test_grep_ripgrep_when_present :: proc(t: ^testing.T) {
	_, has_rg := find_on_path("rg", context.temp_allocator)
	if !has_rg {
		return
	}
	root := "/tmp/nullray-grep-rg"
	_ = os.remove_all(root)
	testing.expect(t, os.make_directory_all(root) == nil)
	defer os.remove_all(root)

	file, jerr := filepath.join({root, "rg.txt"}, context.temp_allocator)
	testing.expect(t, jerr == nil)
	testing.expect(t, os.write_entire_file(file, transmute([]byte)string("needle here\nother\n")) == nil)

	prev := sandbox.workspace_current()
	sandbox.workspace_override_set(root)
	defer {
		if len(prev) > 0 {
			sandbox.workspace_override_set(prev)
		} else {
			sandbox.workspace_override_clear()
		}
	}

	out, err := tool_grep_files(`{"pattern":"needle","path":".","engine":"rg"}`, context.allocator)
	defer delete(out)
	testing.expect(t, err == "")
	testing.expect(t, strings.contains(out, "rg.txt:1:"))
	testing.expect(t, strings.contains(out, "needle"))
}
