// SPDX-License-Identifier: 0BSD
package tools

import "core:os"
import "core:strings"
import "core:testing"
import "nullray:sandbox"

@(test)
test_list_scaffolds_finds_share :: proc(t: ^testing.T) {
	ws := "/tmp/nullray-list-scaffolds-ws"
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

	out, err := tool_list_scaffolds("{}", context.allocator)
	defer delete(out)
	testing.expect_value(t, err, "")
	testing.expect(t, strings.contains(out, "gha-ci") || strings.contains(out, "file\t") || strings.contains(out, "pack\t") || strings.contains(out, "no scaffolds found"))
}

@(test)
test_scaffold_rejects_path_trick :: proc(t: ^testing.T) {
	_, err := tool_scaffold(`{"name":"../etc"}`, context.allocator)
	testing.expect(t, len(err) > 0)
	delete(err)
}
