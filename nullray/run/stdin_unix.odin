// SPDX-License-Identifier: 0BSD
#+build !windows

package run

import "core:os"
import "core:sys/posix"

stdin_is_tty :: proc() -> bool {
	return posix.isatty(posix.STDIN_FILENO) != false
}

read_all_stdin :: proc(allocator := context.allocator) -> (string, bool) {
	if stdin_is_tty() {
		return "", false
	}
	data, err := os.read_entire_file(os.stdin, allocator)
	if err != nil {
		return "", false
	}
	return string(data), true
}
