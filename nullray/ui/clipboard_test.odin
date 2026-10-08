// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package ui

import "core:os"
import "core:testing"

@(test)
test_clipboard_run_stdin_cat_roundtrip :: proc(t: ^testing.T) {
	// clipboard_run_stdin must keep the write end open until after write.
	// Use a simple cat to verify the pipe contract without needing wl-copy.
	when ODIN_OS == .Windows {
		testing.expect(t, true)
		return
	}
	// Not exported: exercise via clipboard_copy path that reaches tools after OSC52.
	// OSC52 always "succeeds" by writing escape to stdout, so force tool path:
	// write a small file with a shell that reads stdin.
	path := "/tmp/nullray-clip-stdin-test"
	_ = os.remove(path)
	ok := clipboard_run_stdin([]string{"sh", "-c", "cat > /tmp/nullray-clip-stdin-test"}, "hello-clip")
	testing.expect(t, ok)
	data, err := os.read_entire_file(path, context.temp_allocator)
	testing.expect(t, err == nil)
	testing.expect_value(t, string(data), "hello-clip")
	_ = os.remove(path)
}
