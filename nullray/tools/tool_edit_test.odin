// SPDX-License-Identifier: 0BSD
package tools

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

@(test)
test_edit_file_exact :: proc(t: ^testing.T) {
	root := "/tmp/nullray-edit-exact"
	_ = os.remove_all(root)
	defer os.remove_all(root)
	testing.expect(t, os.make_directory_all(root) == nil)
	target, _ := filepath.join({root, "a.txt"}, context.temp_allocator)
	testing.expect(t, os.write_entire_file(target, "hello world") == nil)

	args := strings.concatenate(
		{`{"path":"`, target, `","old_string":"world","new_string":"nullray"}`},
		context.temp_allocator,
	)
	result, err := tool_edit_file(args)
	defer delete(result)
	defer delete(err)
	testing.expect(t, len(err) == 0, err)
	testing.expect_value(t, result, "ok")
	data, _ := os.read_entire_file(target, context.temp_allocator)
	testing.expect_value(t, string(data), "hello nullray")
}

@(test)
test_edit_file_fuzzy_crlf :: proc(t: ^testing.T) {
	root := "/tmp/nullray-edit-fuzzy"
	_ = os.remove_all(root)
	defer os.remove_all(root)
	testing.expect(t, os.make_directory_all(root) == nil)
	target, _ := filepath.join({root, "a.txt"}, context.temp_allocator)
	testing.expect(t, os.write_entire_file(target, "one\r\ntwo\r\nthree\r\n") == nil)

	args := strings.concatenate(
		{`{"path":"`, target, `","old_string":"one\ntwo\n","new_string":"ONE\nTWO\n"}`},
		context.temp_allocator,
	)
	result, err := tool_edit_file(args)
	defer delete(result)
	defer delete(err)
	testing.expect(t, len(err) == 0, err)
	testing.expect(t, result == "ok" || result == "ok fuzzy")
	data, _ := os.read_entire_file(target, context.temp_allocator)
	testing.expect(t, strings.contains(string(data), "ONE"))
}

@(test)
test_edit_file_miss_hint :: proc(t: ^testing.T) {
	root := "/tmp/nullray-edit-miss"
	_ = os.remove_all(root)
	defer os.remove_all(root)
	testing.expect(t, os.make_directory_all(root) == nil)
	target, _ := filepath.join({root, "a.txt"}, context.temp_allocator)
	testing.expect(t, os.write_entire_file(target, "alpha\nbeta\n") == nil)

	args := strings.concatenate(
		{`{"path":"`, target, `","old_string":"nope","new_string":"x"}`},
		context.temp_allocator,
	)
	result, err := tool_edit_file(args)
	defer delete(result)
	defer delete(err)
	testing.expect(t, len(err) > 0)
	testing.expect(t, strings.contains(err, "a.txt"))
}

@(test)
test_apply_edits_same_file_chain :: proc(t: ^testing.T) {
	root := "/tmp/nullray-apply-chain"
	_ = os.remove_all(root)
	defer os.remove_all(root)
	testing.expect(t, os.make_directory_all(root) == nil)
	target, _ := filepath.join({root, "a.txt"}, context.temp_allocator)
	testing.expect(t, os.write_entire_file(target, "one two three") == nil)

	args := strings.concatenate(
		{
			`{"edits":[{"path":"`,
			target,
			`","old_string":"one","new_string":"ONE"},{"path":"`,
			target,
			`","old_string":"two","new_string":"TWO"}]}`,
		},
		context.temp_allocator,
	)
	result, err := tool_apply_edits(args)
	defer delete(result)
	defer delete(err)
	testing.expect(t, len(err) == 0, err)
	data, _ := os.read_entire_file(target, context.temp_allocator)
	testing.expect_value(t, string(data), "ONE TWO three")
}
