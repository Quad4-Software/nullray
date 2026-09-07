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

@(private)
probe_ticket :: proc(bin: string) -> bool {
	cmd: string
	if bin == "sudo" {
		cmd = "sudo -n true"
	} else {
		cmd = "doas -n true"
	}
	res := exec_capture(cmd, "", "", "", context.temp_allocator)
	ok := res.exit_code == 0
	result_destroy(&res)
	return ok
}

exec_capture :: proc(
	cmd: string,
	cwd: string,
	sudo_askpass: string,
	doas_askpass: string,
	allocator := context.allocator,
) -> Result {
	stdout_r, stdout_w, pipe_err := os.pipe()
	if pipe_err != nil {
		return Result{
			kind = .Exec_Failed,
			outcome = .Failed,
			err = fmt.aprintf("pipe failed: %v", pipe_err, allocator = allocator),
			exit_code = 1,
		}
	}
	defer os.close(stdout_r)
	stderr_r, stderr_w, pipe_err2 := os.pipe()
	if pipe_err2 != nil {
		os.close(stdout_w)
		return Result{
			kind = .Exec_Failed,
			outcome = .Failed,
			err = fmt.aprintf("pipe failed: %v", pipe_err2, allocator = allocator),
			exit_code = 1,
		}
	}
	defer os.close(stderr_r)

	if len(sudo_askpass) > 0 {
		os.set_env("SUDO_ASKPASS", sudo_askpass)
	}
	if len(doas_askpass) > 0 {
		os.set_env("DOAS_ASKPASS", doas_askpass)
	}

	process: os.Process
	{
		defer os.close(stdout_w)
		defer os.close(stderr_w)
		argv := [3]string{"/bin/sh", "-c", cmd}
		desc := os.Process_Desc{
			working_dir = cwd,
			command = argv[:],
			stdout = stdout_w,
			stderr = stderr_w,
		}
		start_err: os.Error
		process, start_err = os.process_start(desc)
		if start_err != nil {
			return Result{
				kind = .Exec_Failed,
				outcome = .Failed,
				err = fmt.aprintf("exec failed: %v", start_err, allocator = allocator),
				exit_code = 1,
			}
		}
	}

	stdout_b: [dynamic]byte
	stdout_b.allocator = context.temp_allocator
	stderr_b: [dynamic]byte
	stderr_b.allocator = context.temp_allocator
	buf: [1024]u8
	max_out := constants.MAX_SHELL_OUTPUT_BYTES
	timeout := time.Millisecond * time.Duration(constants.SHELL_TIMEOUT_MS)
	start := time.now()
	stdout_done := false
	stderr_done := false
	timed_out := false

	for !stdout_done || !stderr_done {
		if time.since(start) >= timeout {
			timed_out = true
			_ = os.process_kill(process)
			break
		}
		if !stdout_done {
			has_data, read_err := os.pipe_has_data(stdout_r)
			if has_data {
				n, rerr := os.read(stdout_r, buf[:])
				if n > 0 && len(stdout_b) < max_out {
					remain := max_out - len(stdout_b)
					if n > remain {
						n = remain
					}
					append(&stdout_b, ..buf[:n])
				}
				if rerr == io.Error.EOF || rerr == os.General_Error.Broken_Pipe {
					stdout_done = true
				}
			} else if read_err == io.Error.EOF || read_err == os.General_Error.Broken_Pipe {
				stdout_done = true
			}
		}
		if !stderr_done {
			has_data, read_err := os.pipe_has_data(stderr_r)
			if has_data {
				n, rerr := os.read(stderr_r, buf[:])
				if n > 0 && len(stderr_b) < max_out {
					remain := max_out - len(stderr_b)
					if n > remain {
						n = remain
					}
					append(&stderr_b, ..buf[:n])
				}
				if rerr == io.Error.EOF || rerr == os.General_Error.Broken_Pipe {
					stderr_done = true
				}
			} else if read_err == io.Error.EOF || read_err == os.General_Error.Broken_Pipe {
				stderr_done = true
			}
		}
		wait_state, wait_err := os.process_wait(process, 0)
		if wait_err == nil && wait_state.exited {
			for !stdout_done {
				n, rerr := os.read(stdout_r, buf[:])
				if n > 0 && len(stdout_b) < max_out {
					remain := max_out - len(stdout_b)
					if n > remain {
						n = remain
					}
					append(&stdout_b, ..buf[:n])
				}
				if n == 0 || rerr == io.Error.EOF || rerr == os.General_Error.Broken_Pipe {
					stdout_done = true
				}
			}
			for !stderr_done {
				n, rerr := os.read(stderr_r, buf[:])
				if n > 0 && len(stderr_b) < max_out {
					remain := max_out - len(stderr_b)
					if n > remain {
						n = remain
					}
					append(&stderr_b, ..buf[:n])
				}
				if n == 0 || rerr == io.Error.EOF || rerr == os.General_Error.Broken_Pipe {
					stderr_done = true
				}
			}
			break
		}
	}

	state, _ := os.process_wait(process)
	if !state.exited {
		_ = os.process_kill(process)
		state, _ = os.process_wait(process)
	}

	res: Result
	res.exit_code = state.exit_code if state.exited else 1
	if timed_out {
		res.err = strings.clone("timeout", allocator)
		res.exit_code = 1
	}
	if len(stdout_b) > 0 {
		res.stdout = strings.clone(string(stdout_b[:]), allocator)
	}
	if len(stderr_b) > 0 {
		res.stderr = strings.clone(string(stderr_b[:]), allocator)
	}
	return res
}
