// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Elevated command capture and ticket probe.
*/

package elevate

import "core:fmt"
import "core:io"
import "core:os"
import "core:strings"
import "core:time"
import "nullray:constants"
import "nullray:http"

// Per-call drain budget: pipe_has_data loops can be kept alive forever by a
// flooding writer, so a drain returns after this many bytes and lets the
// outer loop re-check timeout and cancel.
@(private)
ELEV_DRAIN_BUDGET :: 64 * 1024

/*
Bounded non-blocking drain for the post-exit path: the child is dead so its
bytes are already kernel-buffered, but a detached grandchild may still hold
the write end open. Read only what pipe_has_data reports ready so a
surviving writer cannot wedge us on a blocking read.
*/
@(private)
elev_drain :: proc(r: ^os.File, b: ^[dynamic]byte, buf: []u8, max_out: int) {
	left := ELEV_DRAIN_BUDGET
	for left > 0 {
		has_data, _ := os.pipe_has_data(r)
		if !has_data {
			return
		}
		n, rerr := os.read(r, buf)
		if n > 0 {
			left -= n
			if len(b^) < max_out {
				take := min(n, max_out - len(b^))
				append(b, ..buf[:take])
			}
		}
		if n == 0 || rerr == io.Error.EOF || rerr == os.General_Error.Broken_Pipe {
			return
		}
	}
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
	elev_claim_process_group(process)

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
	cancelled := false
	state: os.Process_State

	for !stdout_done || !stderr_done {
		if http.cancel_requested() {
			cancelled = true
			elev_kill_process_tree(process)
			break
		}
		if time.since(start) >= timeout {
			timed_out = true
			elev_kill_process_tree(process)
			break
		}
		got_data := false
		if !stdout_done {
			has_data, read_err := os.pipe_has_data(stdout_r)
			if has_data {
				n, rerr := os.read(stdout_r, buf[:])
				got_data = got_data || n > 0
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
				got_data = got_data || n > 0
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
			state = wait_state
			// Child exited, drain only what is already buffered. A detached
			// grandchild holding a write end must not turn this into a
			// blocking read past the timeout.
			elev_drain(stdout_r, &stdout_b, buf[:], max_out)
			elev_drain(stderr_r, &stderr_b, buf[:], max_out)
			break
		}
		if !got_data {
			// Quiet child: avoid a busy spin on poll+waitid.
			time.sleep(2 * time.Millisecond)
		}
	}

	if !state.exited {
		// Timeout and cancel already fired the kill, a pipes-EOF exit with
		// the child still running leaves a blocking wait unbounded. Kill
		// the tree first so the wait is bounded either way.
		elev_kill_process_tree(process)
		state, _ = os.process_wait(process)
	}

	res: Result
	res.exit_code = state.exit_code if state.exited else 1
	if timed_out {
		res.err = strings.clone("timeout", allocator)
		res.exit_code = 1
	} else if cancelled {
		res.err = strings.clone("cancelled", allocator)
		res.exit_code = 1
	} else if !state.exited {
		// Fail closed: no real status was captured.
		res.err = strings.clone("process status unavailable", allocator)
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
