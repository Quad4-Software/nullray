// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
#+build !windows

package main

import posix "core:sys/posix"

/*
Ignore SIGPIPE process-wide. Hook and script-tool stdin writer threads can
race a child that exited early; without this an EPIPE write terminates the
whole process instead of returning a write error.
*/
ignore_sigpipe :: proc "c" (sig: posix.Signal) {
}

install_pipe_signals :: proc() {
	ign: posix.sigaction_t
	ign.sa_handler = ignore_sigpipe
	_ = posix.sigemptyset(&ign.sa_mask)
	_ = posix.sigaction(.SIGPIPE, &ign, nil)
}
