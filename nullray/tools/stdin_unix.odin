// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
#+build !windows

package tools

import "core:sys/posix"

stdin_is_tty :: proc() -> bool {
	return posix.isatty(posix.STDIN_FILENO) != false
}
