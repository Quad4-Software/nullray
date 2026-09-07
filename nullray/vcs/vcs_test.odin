// SPDX-License-Identifier: 0BSD
package vcs

import "core:testing"

@(test)
test_kind_names :: proc(t: ^testing.T) {
	testing.expect_value(t, kind_name(.None), "none")
	testing.expect_value(t, kind_name(.Git), "git")
	testing.expect_value(t, kind_name(.Fossil), "fossil")
}
