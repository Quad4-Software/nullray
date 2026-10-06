// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
#+build linux, darwin, freebsd, openbsd, netbsd
/*
Unix process-group helpers for harness timeouts. Mirrors tools shell_proc.
*/

package harness

import "core:os"
import "core:sys/posix"

harness_claim_process_group :: proc(process: os.Process) {
	if process.pid <= 0 {
		return
	}
	_ = posix.setpgid(posix.pid_t(process.pid), posix.pid_t(process.pid))
}

kill_process_tree :: proc(process: os.Process) {
	if process.pid > 0 {
		_ = posix.kill(posix.pid_t(-process.pid), .SIGKILL)
	}
	_ = os.process_kill(process)
}
