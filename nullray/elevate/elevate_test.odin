// SPDX-License-Identifier: 0BSD
package elevate

import "core:os"
import "core:strings"
import "core:testing"
import "nullray:constants"

@(test)
test_classify_sudo_word_boundary :: proc(t: ^testing.T) {
	c := classify("sudo apt update")
	testing.expect(t, c.needs)
	testing.expect(t, c.backend == .Sudo)
	testing.expect(t, !c.deny_shell)

	c2 := classify("cat /etc/sudoers")
	testing.expect(t, !c2.needs)

	c3 := classify("echo /home/sudoer/file")
	testing.expect(t, !c3.needs)

	c4 := classify("/usr/bin/sudo true")
	testing.expect(t, c4.needs)
	testing.expect(t, c4.backend == .Sudo)
}

@(test)
test_classify_doas_and_pkexec :: proc(t: ^testing.T) {
	c := classify("doas apk add curl")
	testing.expect(t, c.needs)
	testing.expect(t, c.backend == .Doas)

	c2 := classify("pkexec systemctl restart foo")
	testing.expect(t, c2.needs)
	testing.expect(t, c2.backend == .Pkexec)
}

@(test)
test_classify_deny_shells_and_password_args :: proc(t: ^testing.T) {
	c := classify("sudo -i")
	testing.expect(t, c.deny_shell)
	c2 := classify("sudo -s")
	testing.expect(t, c2.deny_shell)
	c3 := classify("doas -s")
	testing.expect(t, c3.deny_shell)
	c4 := classify("su -")
	testing.expect(t, c4.deny_shell)
	c5 := classify("echo secret | sudo -S apt update")
	testing.expect(t, c5.deny_password_args)
	c6 := classify("SUDO_PASSWORD=x sudo -S true")
	testing.expect(t, c6.deny_password_args)
}

@(test)
test_rewrite_sudo_askpass_and_ticket :: proc(t: ^testing.T) {
	rw := rewrite_for_elevate("sudo apt update", .Sudo, "/tmp/askpass", false)
	defer rewrite_destroy(&rw)
	testing.expect(t, strings.contains(rw.command, "sudo -A"))
	testing.expect(t, rw.sudo_askpass == "/tmp/askpass")

	rw2 := rewrite_for_elevate("sudo apt update", .Sudo, "", true)
	defer rewrite_destroy(&rw2)
	testing.expect(t, strings.contains(rw2.command, "sudo -n"))
}

@(test)
test_rewrite_doas_ticket :: proc(t: ^testing.T) {
	rw := rewrite_for_elevate("doas true", .Doas, "/tmp/ask", true)
	defer rewrite_destroy(&rw)
	testing.expect(t, strings.contains(rw.command, "doas -n"))
	testing.expect(t, rw.doas_askpass == "/tmp/ask")
}

@(test)
test_circuit_lockout :: proc(t: ^testing.T) {
	os.set_env(constants.ENV_ELEVATE_MAX_FAILS, "2")
	os.set_env(constants.ENV_ELEVATE_LOCK_SECS, "900")
	defer os.unset_env(constants.ENV_ELEVATE_MAX_FAILS)
	defer os.unset_env(constants.ENV_ELEVATE_LOCK_SECS)
	circuit_reset_for_test()

	ok, _ := circuit_try_enter()
	testing.expect(t, ok)
	circuit_leave()
	circuit_record_failure()
	circuit_record_failure()
	testing.expect(t, circuit_is_locked())
	ok2, why := circuit_try_enter()
	testing.expect(t, !ok2)
	testing.expect(t, why == .Locked)
	circuit_reset_for_test()
}

@(test)
test_circuit_busy :: proc(t: ^testing.T) {
	circuit_reset_for_test()
	ok, _ := circuit_try_enter()
	testing.expect(t, ok)
	ok2, why := circuit_try_enter()
	testing.expect(t, !ok2)
	testing.expect(t, why == .Busy)
	circuit_leave()
	circuit_reset_for_test()
}

@(test)
test_scrub_secret_from_output :: proc(t: ^testing.T) {
	secret := "s3cr3t-pass"
	out := scrub_secret("before s3cr3t-pass after", secret)
	defer delete(out)
	testing.expect(t, !strings.contains(out, secret))
	testing.expect(t, strings.contains(out, REDACTED))

	r := Result{
		stdout = strings.clone("cmd: echo s3cr3t-pass"),
		stderr = strings.clone("warn s3cr3t-pass"),
	}
	scrub_result_inplace(&r, secret)
	testing.expect(t, !strings.contains(r.stdout, secret))
	testing.expect(t, !strings.contains(r.stderr, secret))
	result_destroy(&r)
}

@(test)
test_nonretryable_elevate_text :: proc(t: ^testing.T) {
	testing.expect(t, is_nonretryable_elevate_text("exit_code=1\nelevation=locked\n"))
	testing.expect(t, is_nonretryable_elevate_text("auth_failed"))
	testing.expect(t, !is_nonretryable_elevate_text("exit_code=1\nmake: error"))
}

@(test)
test_run_elevated_denies_password_args :: proc(t: ^testing.T) {
	circuit_reset_for_test()
	r := run_elevated("echo x | sudo -S true", "")
	defer result_destroy(&r)
	testing.expect(t, r.kind == .Denied_Password_Args)
	testing.expect(t, r.outcome == .Denied)
}

@(test)
test_run_elevated_denies_root_shell :: proc(t: ^testing.T) {
	circuit_reset_for_test()
	r := run_elevated("sudo -i", "")
	defer result_destroy(&r)
	testing.expect(t, r.kind == .Denied_Shell)
}

@(test)
test_format_tool_result_no_secret :: proc(t: ^testing.T) {
	r := Result{
		exit_code = 0,
		stdout = strings.clone("ok"),
		outcome = .Ticket,
		kind = .Ok,
	}
	text := format_tool_result(r)
	defer delete(text)
	result_destroy(&r)
	testing.expect(t, strings.contains(text, "elevation=ticket"))
	testing.expect(t, strings.contains(text, "exit_code=0"))
}
