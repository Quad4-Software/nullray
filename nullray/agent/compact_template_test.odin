// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package agent

import "core:strings"
import "core:testing"

@(test)
test_format_compact_fields_wraps_freeform :: proc(t: ^testing.T) {
	out := format_compact_fields("fix the parser")
	defer delete(out)
	testing.expect(t, strings.has_prefix(out, "Goal:"))
	testing.expect(t, strings.contains(out, "fix the parser"))
	testing.expect(t, strings.contains(out, "Files:"))
	testing.expect(t, strings.contains(out, "Errors:"))
	testing.expect(t, strings.contains(out, "Next:"))
	testing.expect(t, strings.contains(out, "Pending steers:"))
}

@(test)
test_format_compact_fields_keeps_headings :: proc(t: ^testing.T) {
	src := "Goal:\nship lint\nFiles:\na.odin\nErrors:\nnone\nNext:\nrun tests"
	out := format_compact_fields(src)
	defer delete(out)
	testing.expect(t, strings.contains(out, "Goal:\nship lint"))
	testing.expect(t, strings.contains(out, "Pending steers:"))
}

@(test)
test_compact_has_headings :: proc(t: ^testing.T) {
	testing.expect(t, compact_has_headings("Goal:\nx\nFiles:\nErrors:\nNext:"))
	testing.expect(t, !compact_has_headings("just a blurb"))
}
