// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
#+build linux, darwin, freebsd, openbsd, netbsd
/*
Unix process-group helpers for elevate timeouts. Mirrors tools shell_proc:
the /bin/sh child becomes a group leader so timeout kills reach sudo and
any grandchildren it spawned.
*/

package elevate

import "core:os"
import "core:sys/posix"

elev_claim_process_group :: proc(process: os.Process) {
	if process.pid <= 0 {
		return
	}
	_ = posix.setpgid(posix.pid_t(process.pid), posix.pid_t(process.pid))
}

elev_kill_process_tree :: proc(process: os.Process) {
	if process.pid > 0 {
		_ = posix.kill(posix.pid_t(-process.pid), .SIGKILL)
	}
	_ = os.process_kill(process)
}
