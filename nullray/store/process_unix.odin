#+build !windows

package store

import "core:fmt"
import "core:os"

@(private)
pid_alive :: proc(pid: int) -> bool {
	if pid <= 0 {
		return false
	}
	return os.exists(fmt.tprintf("/proc/%d", pid))
}
