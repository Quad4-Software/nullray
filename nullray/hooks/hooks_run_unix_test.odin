// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
#+build linux, darwin, freebsd, openbsd, netbsd
package hooks

import "core:os"
import "core:strings"
import "core:sys/posix"
import "core:testing"
import "core:time"
import "nullray:constants"

@(private)
ignore_sigpipe :: proc "c" (sig: posix.Signal) {
}

// Tests that kill pipe readers need SIGPIPE ignored so the writer thread
// sees EPIPE instead of taking down the test binary; the real binary
// installs the same ignore at startup.
@(private)
install_sigpipe_ignore :: proc() {
	act: posix.sigaction_t
	act.sa_handler = ignore_sigpipe
	_ = posix.sigemptyset(&act.sa_mask)
	_ = posix.sigaction(.SIGPIPE, &act, nil)
}

@(private)
set_hook_timeout :: proc(ms: string) -> (had: bool, prev: string) {
	if v, ok := os.lookup_env(constants.ENV_HOOK_TIMEOUT_MS, context.allocator); ok {
		had = true
		prev = v
	}
	os.set_env(constants.ENV_HOOK_TIMEOUT_MS, ms)
	return
}

@(private)
restore_hook_timeout :: proc(had: bool, prev: string) {
	if had {
		os.set_env(constants.ENV_HOOK_TIMEOUT_MS, prev)
		delete(prev)
	} else {
		os.unset_env(constants.ENV_HOOK_TIMEOUT_MS)
	}
}

// Regression: sh exits 7 while a detached sleep still holds stdout open;
// the post-exit drain must stay non-blocking and the real code survive.
@(test)
test_run_command_detached_grandchild_exit :: proc(t: ^testing.T) {
	start := time.now()
	code, timed, _, _ := run_command("sleep 15 & exit 7", "")
	testing.expectf(t, !timed && code == 7, "code=%d timed=%v", code, timed)
	testing.expectf(t, time.since(start) < 10 * time.Second, "detached grandchild wedged")
}

// Regression: a timeout kill of only the direct sh left the backgrounded
// grandchild alive holding stdin, which wedged the writer thread join.
@(test)
test_run_command_timeout_kills_process_group :: proc(t: ^testing.T) {
	install_sigpipe_ignore()
	had, prev := set_hook_timeout("300")
	defer restore_hook_timeout(had, prev)
	big := strings.repeat("x", 256 * 1024, context.temp_allocator)
	start := time.now()
	_, timed, _, _ := run_command("sleep 60 & exec sleep 60", big)
	testing.expect(t, timed)
	testing.expectf(t, time.since(start) < 20 * time.Second, "writer join wedged on surviving grandchild")
}

// Regression: a flooding child kept drain_hook_stdout inside its has_data
// loop so the timeout check never ran.
@(test)
test_run_command_flood_timeout :: proc(t: ^testing.T) {
	had, prev := set_hook_timeout("300")
	defer restore_hook_timeout(had, prev)
	start := time.now()
	_, timed, _, _ := run_command("while :; do echo flood; done", "")
	testing.expect(t, timed)
	testing.expectf(t, time.since(start) < 10 * time.Second, "flood wedged the drain")
}
