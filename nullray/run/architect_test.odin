// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package run

import "core:strings"
import "core:testing"

@(test)
test_architect_plan_prompt :: proc(t: ^testing.T) {
	p := architect_plan_prompt("add rewind")
	defer delete(p)
	testing.expect(t, strings.contains(p, "## Goal"))
	testing.expect(t, strings.contains(p, "## Verify"))
	testing.expect(t, strings.contains(p, "add rewind"))
}
