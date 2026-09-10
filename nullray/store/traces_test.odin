// SPDX-License-Identifier: 0BSD
/*
Trace store stress tests.
*/

package store

import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"
import "core:time"
import "nullray:constants"

@(test)
test_trace_store_writes_skill_draft :: proc(t: ^testing.T) {
	ws := fmt.tprintf("/run/media/user1/projects/pie/.tmp/nullray-trace-test-%d", time.time_to_unix(time.now()))
	_ = os.remove_all(ws)
	testing.expect(t, os.make_directory_all(ws) == nil)
	defer os.remove_all(ws)
	prev, had := os.lookup_env(constants.ENV_WORKSPACE, context.allocator)
	os.set_env(constants.ENV_WORKSPACE, ws)
	defer {
		if had {
			os.set_env(constants.ENV_WORKSPACE, prev)
			delete(prev)
		} else {
			os.unset_env(constants.ENV_WORKSPACE)
		}
	}
	path := trace_store_verify_fail("make test", "secret api_key=sk-test-should-redact\nfoo.odin(1:1) error", 1, context.allocator)
	defer delete(path)
	testing.expect(t, len(path) > 0)
	data, err := os.read_entire_file(path, context.allocator)
	testing.expect(t, err == nil)
	defer delete(data)
	body := string(data)
	testing.expect(t, strings.contains(body, "make test"))
	dir := traces_dir(context.temp_allocator)
	entries, _ := os.read_directory_by_path(dir, -1, context.temp_allocator)
	found_draft := false
	for e in entries {
		if strings.contains(e.name, "skill_draft") {
			found_draft = true
		}
	}
	testing.expect(t, found_draft)
}
