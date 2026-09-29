// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
#+build !windows

package session

import "core:fmt"
import "core:os"

@(private)
process_alive :: proc(pid: int) -> bool {
	if pid <= 0 {
		return false
	}
	path := fmt.tprintf("/proc/%d", pid)
	return os.exists(path)
}
