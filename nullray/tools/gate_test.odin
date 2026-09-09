// SPDX-License-Identifier: 0BSD
package tools

import "core:os"
import "core:testing"
import "nullray:constants"

@(test)
test_gate_parse_aliases :: proc(t: ^testing.T) {
	n, ok := gate_parse("ask")
	testing.expect(t, ok)
	testing.expect_value(t, n, 0)
	n2, ok2 := gate_parse("yolo")
	testing.expect(t, ok2)
	testing.expect_value(t, n2, 3)
	n3, ok3 := gate_parse("2")
	testing.expect(t, ok3)
	testing.expect_value(t, n3, 2)
}

@(test)
test_gate_blocks_write_at_zero :: proc(t: ^testing.T) {
	os.set_env(constants.ENV_GATE, "0")
	defer os.unset_env(constants.ENV_GATE)
	r: Registry
	registry_init(&r)
	defer registry_destroy(&r)
	ok, reason := gate_allows_tool(&r, "write_file")
	testing.expect(t, !ok)
	testing.expect(t, len(reason) > 0)
	ok2, _ := gate_allows_tool(&r, "read_file")
	testing.expect(t, ok2)
}

@(test)
test_gate_shell_needs_two :: proc(t: ^testing.T) {
	os.set_env(constants.ENV_GATE, "1")
	defer os.unset_env(constants.ENV_GATE)
	r: Registry
	registry_init(&r)
	defer registry_destroy(&r)
	ok, reason := gate_allows_tool(&r, "run_shell")
	testing.expect(t, !ok)
	testing.expect(t, len(reason) > 0)
}
