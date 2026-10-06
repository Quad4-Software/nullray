// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package tools

import "core:strings"
import "core:testing"

@(test)
test_bg_new_id_nonzero :: proc(t: ^testing.T) {
	id := bg_new_id()
	defer delete(id)
	testing.expect(t, len(id) > 4)
}

@(test)
test_shell_bg_poll_unknown :: proc(t: ^testing.T) {
	_, err := shell_bg_poll("no-such-task")
	defer delete(err)
	testing.expect(t, len(err) > 0)
	testing.expect(t, strings.contains(err, "unknown task_id"))
}

@(test)
test_json_arg_bool_native_and_string :: proc(t: ^testing.T) {
	v, err := json_arg_bool(`{"background":true}`, "background", false)
	testing.expect_value(t, err, "")
	testing.expect(t, v)
	v2, err2 := json_arg_bool(`{"background":"true"}`, "background", false)
	testing.expect_value(t, err2, "")
	testing.expect(t, v2)
	v3, err3 := json_arg_bool(`{}`, "background", false)
	testing.expect_value(t, err3, "")
	testing.expect(t, !v3)
}
