// SPDX-License-Identifier: 0BSD
package tools

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

@(test)
test_apply_edits_replace_and_create :: proc(t: ^testing.T) {
	root := "/tmp/nullray-apply-edits-test"
	_ = os.remove_all(root)
	defer os.remove_all(root)
	testing.expect(t, os.make_directory_all(root) == nil)

	target, terr := filepath.join({root, "a.txt"}, context.temp_allocator)
	testing.expect(t, terr == nil)
	testing.expect(t, os.write_entire_file(target, "alpha beta") == nil)

	created, cerr := filepath.join({root, "b.txt"}, context.temp_allocator)
	testing.expect(t, cerr == nil)

	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	strings.write_string(&b, `{"edits":[{"path":"`)
	strings.write_string(&b, target)
	strings.write_string(
		&b,
		`","old_string":"beta","new_string":"gamma","replace_all":"false"}],"files":[{"path":"`,
	)
	strings.write_string(&b, created)
	strings.write_string(&b, `","content":"new file"}]}`)
	args := strings.to_string(b)

	result, err := tool_apply_edits(args)
	defer delete(result)
	defer delete(err)
	testing.expect(t, len(err) == 0, err)
	testing.expect(t, strings.has_prefix(result, "ok applied=2"))

	data, read_err := os.read_entire_file(target, context.temp_allocator)
	testing.expect(t, read_err == nil)
	testing.expect_value(t, string(data), "alpha gamma")

	data2, read_err2 := os.read_entire_file(created, context.temp_allocator)
	testing.expect(t, read_err2 == nil)
	testing.expect_value(t, string(data2), "new file")
}
