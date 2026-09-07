// SPDX-License-Identifier: 0BSD
#+build !linux
/*
pkexec stub outside Linux.
*/

package elevate

import "core:strings"

polkit_session_agent_present :: proc() -> bool {
	return false
}

run_pkexec :: proc(cmd: string, cwd: string, allocator := context.allocator) -> Result {
	_ = cmd
	_ = cwd
	return Result{
		backend = .Pkexec,
		outcome = .Unsupported,
		kind = .Unsupported,
		exit_code = 1,
		err = strings.clone("pkexec/polkit is Linux-only", allocator),
	}
}
