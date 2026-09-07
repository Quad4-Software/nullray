// SPDX-License-Identifier: 0BSD
#+build linux, darwin, freebsd, openbsd, netbsd
/*
Unix process-group helpers for shell timeouts.
*/

package tools

import "core:os"
import "core:sys/posix"

shell_claim_process_group :: proc(process: os.Process) {
	if process.pid <= 0 {
		return
	}
	_ = posix.setpgid(posix.pid_t(process.pid), posix.pid_t(process.pid))
}

shell_kill_process_tree :: proc(process: os.Process) {
	if process.pid > 0 {
		_ = posix.kill(posix.pid_t(-process.pid), .SIGKILL)
	}
	_ = os.process_kill(process)
}
