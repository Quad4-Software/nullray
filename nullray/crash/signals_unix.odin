// SPDX-License-Identifier: 0BSD
#+build !windows

/*
POSIX fatal signal handlers. Restore the TTY then dump a report.
*/

package crash

import "base:runtime"
import "core:sys/posix"
import "nullray:ui"

install_signals :: proc() {
	act: posix.sigaction_t
	act.sa_handler = fatal_signal
	act.sa_flags = {.RESETHAND}
	_ = posix.sigemptyset(&act.sa_mask)

	_ = posix.sigaction(.SIGSEGV, &act, nil)
	_ = posix.sigaction(.SIGABRT, &act, nil)
	_ = posix.sigaction(.SIGBUS, &act, nil)
	_ = posix.sigaction(.SIGFPE, &act, nil)
	_ = posix.sigaction(.SIGILL, &act, nil)
}

@(private)
fatal_signal :: proc "c" (sig: posix.Signal) {
	ui.term_emergency_restore()
	context = runtime.default_context()
	name := "SIGNAL"
	#partial switch sig {
	case .SIGSEGV:
		name = "SIGSEGV"
	case .SIGABRT:
		name = "SIGABRT"
	case .SIGBUS:
		name = "SIGBUS"
	case .SIGFPE:
		name = "SIGFPE"
	case .SIGILL:
		name = "SIGILL"
	}
	handle_fatal_signal(int(sig), name)
}
