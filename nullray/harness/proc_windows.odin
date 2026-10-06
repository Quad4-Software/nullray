// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
#+build windows
/*
Windows process-tree kill for harness timeouts. Mirrors tools shell_proc.
*/

package harness

import "core:fmt"
import "core:os"

harness_claim_process_group :: proc(process: os.Process) {
	_ = process
}

kill_process_tree :: proc(process: os.Process) {
	if process.pid > 0 {
		cmd := fmt.tprintf("taskkill /PID %d /T /F", process.pid)
		argv := [3]string{"cmd.exe", "/C", cmd}
		desc := os.Process_Desc{command = argv[:]}
		if killer, err := os.process_start(desc); err == nil {
			_, _ = os.process_wait(killer)
		}
	}
	_ = os.process_kill(process)
}
