// SPDX-License-Identifier: 0BSD
#+build !windows

/*
stdin_ready via posix.poll.
*/

package ui

import "core:sys/posix"

@(private)
stdin_ready :: proc(timeout_ms: int) -> bool {
	if _has_pushback {
		return true
	}
	pfd := posix.pollfd{
		fd = posix.STDIN_FILENO,
		events = {.IN},
	}
	n := posix.poll(&pfd, 1, i32(timeout_ms))
	return n > 0 && ((.IN in pfd.revents) || (.HUP in pfd.revents) || (.ERR in pfd.revents))
}
