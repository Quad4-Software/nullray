// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package app

import "core:os"
import "core:strings"
import "core:testing"

@(test)
test_expand_command_template :: proc(t: ^testing.T) {
	out := expand_command_template("Fix $ARGUMENTS and file $1", "issue-12 src/a.go")
	defer delete(out)
	testing.expect(t, strings.contains(out, "Fix issue-12 src/a.go"))
	testing.expect(t, strings.contains(out, "file issue-12"))
}

@(test)
test_custom_commands_reload_empty :: proc(t: ^testing.T) {
	os.set_env("NULLRAY_WORKSPACE", "/tmp/nullray-no-commands")
	defer os.unset_env("NULLRAY_WORKSPACE")
	custom_commands_reload()
	_, ok := custom_command_find("does-not-exist")
	testing.expect(t, !ok)
}
