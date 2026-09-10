// SPDX-License-Identifier: 0BSD
package vcs

import "core:testing"

@(test)
test_scope_names_and_parse :: proc(t: ^testing.T) {
	testing.expect_value(t, scope_name(.Working), "working")
	testing.expect_value(t, scope_name(.Staged), "staged")
	s, ok := scope_from_string("staged")
	testing.expect(t, ok)
	testing.expect_value(t, s, Diff_Scope.Staged)
	s2, ok2 := scope_from_string("uncommitted")
	testing.expect(t, ok2)
	testing.expect_value(t, s2, Diff_Scope.Unstaged)
	_, bad := scope_from_string("nope")
	testing.expect(t, !bad)
}

@(test)
test_kind_names :: proc(t: ^testing.T) {
	testing.expect_value(t, kind_name(.None), "none")
	testing.expect_value(t, kind_name(.Git), "git")
	testing.expect_value(t, kind_name(.Fossil), "fossil")
}
