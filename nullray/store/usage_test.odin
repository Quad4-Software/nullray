// SPDX-License-Identifier: 0BSD
package store

import "core:os"
import "core:testing"

@(test)
test_usage_path_and_append_roundtrip :: proc(t: ^testing.T) {
	dir := "/tmp/nullray-usage-test"
	_ = os.make_directory_all(dir)
	path := "/tmp/nullray-usage-test/sess.jsonl"
	_ = os.remove(path)
	_ = os.remove(usage_path_for(path, context.temp_allocator))
	defer {
		_ = os.remove(path)
		_ = os.remove(usage_path_for(path, context.temp_allocator))
	}
	testing.expect(t, append_turn_metrics(path, Turn_Metrics{
		turn = 1,
		model = "m",
		prompt_tokens = 3,
		completion_tokens = 2,
		total_tokens = 5,
		cost_usd = 0.01,
		cost_known = true,
		stopped = "done",
	}))
	m, ok := load_session_metrics(path)
	testing.expect(t, ok)
	defer delete(m.model)
	defer delete(m.provider)
	testing.expect_value(t, m.turns, 1)
	testing.expect_value(t, m.total_tokens, 5)
	testing.expect(t, m.cost_known)
}
