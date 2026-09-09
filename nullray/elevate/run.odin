// SPDX-License-Identifier: 0BSD
/*
Run elevated commands via ticket probe, askpass, or broker.
*/

package elevate

import "core:fmt"
import "core:io"
import "core:os"
import "core:strings"
import "core:time"
import "nullray:constants"

run_elevated :: proc(
	cmd: string,
	cwd: string,
	allocator := context.allocator,
) -> Result {
	cl := classify(cmd)
	if !cl.needs {
		return Result{
			kind = .Exec_Failed,
			outcome = .Denied,
			err = strings.clone("not an elevated command", allocator),
		}
	}
	if cl.deny_password_args {
		return Result{
			kind = .Denied_Password_Args,
			outcome = .Denied,
			backend = cl.backend,
			err = strings.clone(
				"denied: password must not appear in shell args (use nullray elevate UI)",
				allocator,
			),
		}
	}
	if cl.deny_shell {
		return Result{
			kind = .Denied_Shell,
			outcome = .Denied,
			backend = cl.backend,
			err = strings.clone("denied: interactive root shells are blocked", allocator),
		}
	}
	if elevate_mode_from_env() == .Deny {
		return Result{
			kind = .Denied_Shell,
			outcome = .Denied,
			backend = cl.backend,
			err = strings.clone("elevation disabled (NULLRAY_ELEVATE=deny)", allocator),
		}
	}
	when ODIN_OS == .Windows {
		if cl.backend == .Pkexec || cl.backend == .Doas {
			return Result{
				kind = .Unsupported,
				outcome = .Unsupported,
				backend = cl.backend,
				err = strings.clone("pkexec/doas unsupported on Windows", allocator),
			}
		}
	} else {
		if cl.backend == .Runas {
			return Result{
				kind = .Unsupported,
				outcome = .Unsupported,
				backend = cl.backend,
				err = strings.clone("runas unsupported on this OS", allocator),
			}
		}
	}
	if cl.backend == .Su {
		return Result{
			kind = .Denied_Shell,
			outcome = .Denied,
			backend = .Su,
			err = strings.clone("denied: su is blocked; use sudo or doas", allocator),
		}
	}

	ok, why := circuit_try_enter()
	if !ok {
		r := Result{
			backend = cl.backend,
			outcome = why,
			exit_code = 1,
		}
		if why == .Locked {
			r.kind = .Locked
			r.err = strings.clone("elevation_locked: too many auth failures", allocator)
		} else {
			r.kind = .Busy
			r.err = strings.clone("elevation_busy: another elevate is in progress", allocator)
		}
		return r
	}
	defer circuit_leave()

	when ODIN_OS == .Windows {
		return run_elevated_windows(cmd, cwd, cl.backend, allocator)
	} else {
		return run_elevated_unix(cmd, cwd, cl.backend, allocator)
	}
}

@(private)
run_elevated_unix :: proc(
	cmd: string,
	cwd: string,
	backend: Backend,
	allocator := context.allocator,
) -> Result {
	mode := elevate_mode_from_env()

	if backend == .Pkexec {
		return run_pkexec(cmd, cwd, allocator)
	}

	ticket_ok := false
	if backend == .Sudo {
		ticket_ok = probe_ticket("sudo")
	} else if backend == .Doas {
		ticket_ok = probe_ticket("doas")
	}

	if ticket_ok {
		rw := rewrite_for_elevate(cmd, backend, "", true, context.temp_allocator)
		res := exec_capture(rw.command, cwd, "", "", allocator)
		res.backend = backend
		if res.exit_code == 0 {
			res.outcome = .Ticket
			res.kind = .Ok
			circuit_record_success()
		} else if auth_failure_text(res.stderr) {
			res.outcome = .Failed
			res.kind = .Auth_Failed
			circuit_record_failure()
		} else {
			res.outcome = .Failed
			res.kind = .Exec_Failed
		}
		return res
	}

	if mode == .Ticket {
		return Result{
			backend = backend,
			outcome = .Needs_Tty,
			kind = .Needs_Tty,
			exit_code = 1,
			err = strings.clone(
				"elevation_needs_tty: no cached ticket (NULLRAY_ELEVATE=ticket)",
				allocator,
			),
		}
	}

	if headless() && !secret_ui_enabled() {
		ext, has_ext := os.lookup_env(constants.ENV_ASKPASS, context.temp_allocator)
		if !has_ext || len(strings.trim_space(ext)) == 0 {
			return Result{
				backend = backend,
				outcome = .Needs_Tty,
				kind = .Needs_Tty,
				exit_code = 1,
				err = strings.clone(
					"elevation_needs_tty: no TUI and no NULLRAY_ASKPASS / cached ticket",
					allocator,
				),
			}
		}
	}

	ask := askpass_path(context.temp_allocator)
	// Prefer in-process askpass via UI sock helper wrapper.
	helper := ensure_askpass_helper(context.temp_allocator)
	if len(helper) > 0 {
		ask = helper
	}

	rw := rewrite_for_elevate(cmd, backend, ask, false)
	defer rewrite_destroy(&rw)

	sudo_env := rw.sudo_askpass
	doas_env := rw.doas_askpass

	// Prefill password into secret channel by driving modal before spawn when UI enabled.
	password: string
	used_pw := false
	if secret_ui_enabled() && !headless() {
		pw, ok, cancelled := request_password(
			"Password for elevated command:",
			cmd,
			modal_secs_from_env(),
			context.allocator,
		)
		if cancelled {
			circuit_record_failure()
			return Result{
				backend = backend,
				outcome = .Cancelled,
				kind = .Auth_Cancelled,
				exit_code = 1,
				err = strings.clone("auth_cancelled", allocator),
			}
		}
		if !ok {
			return Result{
				backend = backend,
				outcome = .Needs_Tty,
				kind = .Needs_Tty,
				exit_code = 1,
				err = strings.clone("elevation_needs_tty: password prompt unavailable", allocator),
			}
		}
		password = pw
		used_pw = true
		// Stash for askpass helper to read once.
		stash_askpass_secret(password)
	}

	res: Result
	if broker_available() {
		res = broker_run(rw.command, cwd, sudo_env, doas_env, allocator)
	} else {
		res = exec_capture(rw.command, cwd, sudo_env, doas_env, allocator)
	}
	res.backend = backend
	res.used_password = used_pw

	if used_pw {
		scrub_result_inplace(&res, password)
		zero_and_delete(password)
		clear_askpass_secret()
	}

	if res.exit_code == 0 {
		res.outcome = .Askpass
		res.kind = .Ok
		circuit_record_success()
		return res
	}
	if requiretty_text(res.stderr) {
		res.outcome = .Failed
		res.kind = .Requiretty
		if len(res.err) == 0 {
			res.err = strings.clone(
				"sudo requiretty blocked askpass; enable askpass or Defaults !requiretty",
				allocator,
			)
		}
		return res
	}
	if auth_failure_text(res.stderr) || auth_failure_text(res.err) {
		res.outcome = .Failed
		res.kind = .Auth_Failed
		circuit_record_failure()
		if len(res.err) == 0 {
			res.err = strings.clone("auth_failed", allocator)
		}
		return res
	}
	res.outcome = .Failed
	res.kind = .Exec_Failed
	return res
}
