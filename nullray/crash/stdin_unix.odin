// SPDX-License-Identifier: 0BSD
#+build !windows

package crash

import "core:sys/posix"

stdin_is_tty :: proc() -> bool {
	return bool(posix.isatty(posix.STDIN_FILENO))
}
