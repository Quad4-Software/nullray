// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package tools

import "core:strconv"
import "core:strings"
import "core:testing"
import "core:time"
import "nullray:constants"

@(test)
test_run_process_capture_small_output :: proc(t: ^testing.T) {
	when ODIN_OS == .Windows {
		return
	}
	argv := []string{"/bin/sh", "-c", "echo hello; echo oops >&2"}
	res, err := run_process_capture(argv, ".", 10_000, context.allocator)
	defer delete(res)
	testing.expect_value(t, err, "")
	testing.expectf(t, strings.contains(res, "exit_code=0"), "res=%q", res)
	testing.expectf(t, strings.contains(res, "hello"), "res=%q", res)
	testing.expectf(t, strings.contains(res, "oops"), "res=%q", res)
	testing.expectf(t, !strings.contains(res, "truncated"), "res=%q", res)
	testing.expectf(t, !strings.contains(res, "unavailable"), "res=%q", res)
}

// Regression: the in-loop non-blocking wait already reaps the child, so a
// later blocking wait used to fabricate exit_code=1 plus "unavailable".
@(test)
test_run_process_capture_exit_code_nonzero :: proc(t: ^testing.T) {
	when ODIN_OS == .Windows {
		return
	}
	argv := []string{"/bin/sh", "-c", "exit 7"}
	res, err := run_process_capture(argv, ".", 10_000, context.allocator)
	defer delete(res)
	testing.expect_value(t, err, "")
	testing.expectf(t, strings.contains(res, "exit_code=7"), "res=%q", res)
	testing.expectf(t, !strings.contains(res, "process status unavailable"), "res=%q", res)
	testing.expectf(t, !strings.contains(res, "exit_code=1"), "res=%q", res)
}

@(test)
test_run_process_capture_exit_code_zero :: proc(t: ^testing.T) {
	when ODIN_OS == .Windows {
		return
	}
	argv := []string{"/bin/sh", "-c", "exit 0"}
	res, err := run_process_capture(argv, ".", 10_000, context.allocator)
	defer delete(res)
	testing.expect_value(t, err, "")
	testing.expectf(t, strings.contains(res, "exit_code=0"), "res=%q", res)
	testing.expectf(t, !strings.contains(res, "process status unavailable"), "res=%q", res)
}

@(test)
test_run_process_capture_head_tail_truncation :: proc(t: ^testing.T) {
	when ODIN_OS == .Windows {
		return
	}
	fill := 100_000
	total := len("HEAD-MARKER\n") + fill + len("\nTAIL-MARKER\n")
	argv := []string {
		"/bin/sh",
		"-c",
		"printf 'HEAD-MARKER\\n'; head -c 100000 /dev/zero | tr '\\0' 'x'; printf '\\nTAIL-MARKER\\n'",
	}
	res, err := run_process_capture(argv, ".", 10_000, context.allocator)
	defer delete(res)
	testing.expect_value(t, err, "")
	testing.expectf(t, strings.contains(res, "exit_code=0"), "res=%q", res)
	testing.expectf(t, strings.contains(res, "HEAD-MARKER"), "head lost, res head=%q", res[:min(len(res), 200)])
	testing.expectf(t, strings.contains(res, "TAIL-MARKER"), "tail lost, res tail=%q", res[max(0, len(res) - 200):])

	head_idx := strings.index(res, "HEAD-MARKER")
	mark_idx := strings.index(res, "[truncated ")
	tail_idx := strings.index(res, "TAIL-MARKER")
	testing.expectf(t, head_idx >= 0 && mark_idx > head_idx && tail_idx > mark_idx,
		"marker not between head and tail: %d %d %d", head_idx, mark_idx, tail_idx)

	// Dropped count must equal bytes seen minus the kept head+tail budget.
	digits := res[mark_idx + len("[truncated "):]
	end := strings.index(digits, " bytes]")
	testing.expect(t, end > 0)
	n, ok := strconv.parse_int(digits[:end])
	testing.expect(t, ok)
	testing.expect_value(t, n, total - constants.MAX_SHELL_OUTPUT_BYTES)
}

@(test)
test_run_process_capture_stderr_tail :: proc(t: ^testing.T) {
	when ODIN_OS == .Windows {
		return
	}
	argv := []string {
		"/bin/sh",
		"-c",
		"echo OUT; head -c 80000 /dev/zero | tr '\\0' 'e' >&2; echo ERR-TAIL >&2",
	}
	res, err := run_process_capture(argv, ".", 10_000, context.allocator)
	defer delete(res)
	testing.expect_value(t, err, "")
	testing.expectf(t, strings.contains(res, "OUT"), "res=%q", res[:min(len(res), 200)])
	testing.expectf(t, strings.contains(res, "ERR-TAIL"), "stderr tail lost, res tail=%q", res[max(0, len(res) - 200):])
	testing.expectf(t, strings.contains(res, "[truncated "), "res=%q", res[:min(len(res), 200)])
}

@(test)
test_run_process_capture_timeout :: proc(t: ^testing.T) {
	when ODIN_OS == .Windows {
		return
	}
	start := time.now()
	argv := []string{"/bin/sh", "-c", "sleep 30"}
	res, err := run_process_capture(argv, ".", 300, context.allocator)
	defer delete(res)
	testing.expect_value(t, err, "")
	testing.expectf(t, strings.has_prefix(res, "timeout"), "res=%q", res)
	testing.expectf(t, strings.contains(res, "exit_code="), "res=%q", res)
	testing.expectf(t, time.since(start) < 10 * time.Second, "timeout path took too long")
}

// Regression: a detached grandchild holding the pipe write end used to
// wedge the post-exit blocking drain well past the real child exit.
@(test)
test_run_process_capture_detached_grandchild :: proc(t: ^testing.T) {
	when ODIN_OS == .Windows {
		return
	}
	start := time.now()
	argv := []string{"/bin/sh", "-c", "sleep 15 & exit 7"}
	res, err := run_process_capture(argv, ".", 20_000, context.allocator)
	defer delete(res)
	testing.expect_value(t, err, "")
	testing.expectf(t, strings.contains(res, "exit_code=7"), "res=%q", res)
	testing.expectf(t, time.since(start) < 10 * time.Second, "detached grandchild wedged the drain")
}

// Regression: a child that redirects its streams away and keeps running
// used to hang the post-loop blocking wait; it is killed now.
@(test)
test_run_process_capture_pipes_eof_running_child :: proc(t: ^testing.T) {
	when ODIN_OS == .Windows {
		return
	}
	start := time.now()
	argv := []string{"/bin/sh", "-c", "exec >/dev/null 2>&1; sleep 15"}
	res, err := run_process_capture(argv, ".", 20_000, context.allocator)
	defer delete(res)
	testing.expect_value(t, err, "")
	testing.expectf(t, strings.contains(res, "exit_code="), "res=%q", res)
	testing.expectf(t, time.since(start) < 10 * time.Second, "pipes-EOF running child wedged the wait")
}
