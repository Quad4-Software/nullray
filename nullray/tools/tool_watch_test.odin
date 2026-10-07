// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
watch_checkpoint tool coverage: arg parsing, the delta gate contract
("no new items" on repeat runs), and notification suppression on the
no-delta path (NULLRAY_NOTIFY=off makes send a noop regardless).
*/

package tools

import "core:os"
import "core:fmt"
import "core:strings"
import "core:testing"
import "nullray:constants"
import "nullray:sandbox"
import "nullray:schedule"

@(private)
watch_tool_setup :: proc(t: ^testing.T) -> string {
	root := "/tmp/nullray-toolwatch-test"
	_ = os.remove_all(root)
	testing.expect(t, os.make_directory_all(root) == nil)
	sandbox.workspace_override_set(root)
	// Belt and suspenders: keep notifications inert in CI.
	os.set_env(constants.ENV_NOTIFY, "off")
	schedule.schedule_init()
	return root
}

@(private)
watch_tool_teardown :: proc(root: string) {
	sandbox.workspace_override_clear()
	os.unset_env(constants.ENV_NOTIFY)
	_ = os.remove_all(root)
}

@(test)
test_watch_checkpoint_tool_delta :: proc(t: ^testing.T) {
	root := watch_tool_setup(t)
	defer watch_tool_teardown(root)

	id, aerr := schedule.watch_add("tool test", "every 1h", "", 0, 0, 0, schedule.unix_now())
	testing.expect_value(t, aerr, "")
	id_str := fmt.tprintf("%d", id)
	args := strings.concatenate({`{"id":"`, id_str, `","items":["CVE-1","CVE-2"],"note":"first"}`}, context.temp_allocator)
	out, err := tool_watch_checkpoint(args, context.allocator)
	defer delete(out)
	testing.expect_value(t, err, "")
	testing.expect(t, strings.contains(out, "2 new item"))

	// Repeat set: zero new items, so the tool stays silent on notify.
	out2, err2 := tool_watch_checkpoint(
		strings.concatenate({`{"id":"`, id_str, `","items":["CVE-2","CVE-1"],"note":"repeat"}`}, context.temp_allocator),
		context.allocator,
	)
	defer delete(out2)
	testing.expect_value(t, err2, "")
	testing.expect(t, strings.contains(out2, "no new items"))

	// items as an embedded JSON string also parses.
	out3, err3 := tool_watch_checkpoint(
		strings.concatenate({`{"id":"`, id_str, `","items":"[\"CVE-3\"]"}`}, context.temp_allocator),
		context.allocator,
	)
	defer delete(out3)
	testing.expect_value(t, err3, "")
	testing.expect(t, strings.contains(out3, "1 new item"))
}

@(test)
test_watch_checkpoint_tool_bad_args :: proc(t: ^testing.T) {
	root := watch_tool_setup(t)
	defer watch_tool_teardown(root)
	_, err := tool_watch_checkpoint(`{"items":["a"]}`, context.allocator)
	defer delete(err)
	testing.expect(t, strings.contains(err, "id"))
	_, err2 := tool_watch_checkpoint(`{"id":"42"}`, context.allocator)
	defer delete(err2)
	testing.expect(t, strings.contains(err2, "items"))
}

