// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
harness_list / harness_run wiring: registration, kinds, env disable.
*/

package tools

import "core:os"
import "core:strings"
import "core:testing"
import "nullray:constants"

@(test)
test_harness_tools_registered :: proc(t: ^testing.T) {
	r: Registry
	registry_init(&r)
	defer registry_destroy(&r)
	_, found := registry_find(&r, "harness_list")
	testing.expect(t, found)
	hr, found2 := registry_find(&r, "harness_run")
	testing.expect(t, found2)
	testing.expect_value(t, hr.kind, Tool_Kind.Shell)

	res, err := tool_harness_list(`{}`)
	testing.expect(t, len(err) == 0, err)
	defer delete(res)
	testing.expect(t, strings.contains(res, "claude"), res)
	testing.expect(t, strings.contains(res, "opencode"), res)
}

@(test)
test_harness_run_bad_engine :: proc(t: ^testing.T) {
	_, err := tool_harness_run(`{"engine":"nope-x","prompt":"hi"}`)
	testing.expect(t, strings.contains(err, "unknown harness"), err)
	delete(err)
}

@(test)
test_harness_disabled_env :: proc(t: ^testing.T) {
	had, prev := "", ""
	if v, ok := os.lookup_env(constants.ENV_HARNESS, context.allocator); ok {
		had = "1"
		prev = v
	}
	os.set_env(constants.ENV_HARNESS, "0")
	defer {
		if had == "1" {
			os.set_env(constants.ENV_HARNESS, prev)
			delete(prev)
		} else {
			os.unset_env(constants.ENV_HARNESS)
		}
	}
	_, err := tool_harness_list(`{}`)
	testing.expect(t, strings.contains(err, "disabled"))
	delete(err)
	_, err2 := tool_harness_run(`{"engine":"claude","prompt":"hi"}`)
	testing.expect(t, strings.contains(err2, "disabled"))
	delete(err2)
}
