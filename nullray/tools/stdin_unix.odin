// SPDX-License-Identifier: 0BSD
#+build !windows

package tools

import "core:sys/posix"

stdin_is_tty :: proc() -> bool {
	return posix.isatty(posix.STDIN_FILENO) != false
}
