// SPDX-License-Identifier: 0BSD
package agent

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

@(test)
test_parse_findings_trailer :: proc(t: ^testing.T) {
	n, ok := parse_findings_trailer("looks fine\n\nFINDINGS: none\n")
	testing.expect(t, ok)
	testing.expect_value(t, n, 0)

	n2, ok2 := parse_findings_trailer("issue one\nFINDINGS: 2")
	testing.expect(t, ok2)
	testing.expect_value(t, n2, 2)

	_, ok3 := parse_findings_trailer("no trailer here")
	testing.expect(t, !ok3)
}

@(test)
test_resolve_plan_path_priority :: proc(t: ^testing.T) {
	p := resolve_plan_path("/tmp/explicit.md", "/tmp/out.md", "/ws")
	defer delete(p)
	testing.expect_value(t, p, "/tmp/explicit.md")

	p2 := resolve_plan_path("", "/tmp/out.md", "/ws")
	defer delete(p2)
	testing.expect_value(t, p2, "/tmp/out.md")

	p3 := resolve_plan_path("", "", "/tmp/ws")
	defer delete(p3)
	testing.expect(t, strings.has_prefix(p3, "/tmp/ws/"))
	testing.expect(t, strings.has_suffix(p3, ".md"))
}

@(test)
test_save_plan_artifact :: proc(t: ^testing.T) {
	root := "/tmp/nullray-plan-test"
	_ = os.make_directory_all(root)
	out, jerr := filepath.join({root, "plan.md"}, context.temp_allocator)
	testing.expect(t, jerr == nil)
	path, err := save_plan_artifact("# Title\n\nsteps", out, "", "")
	defer delete(path)
	testing.expect_value(t, err, "")
	testing.expect_value(t, path, out)
	data, rerr := os.read_entire_file(path, context.allocator)
	testing.expect(t, rerr == nil)
	defer delete(data)
	testing.expect_value(t, string(data), "# Title\n\nsteps")
}
