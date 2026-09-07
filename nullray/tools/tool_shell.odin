// SPDX-License-Identifier: 0BSD
/*
run_shell tool: execute /bin/sh -c in workspace when sandbox permits.
*/

package tools

import "core:fmt"
import "core:io"
import "core:os"
import "core:strings"
import "core:time"
import "nullray:constants"
import "nullray:elevate"
import "nullray:sandbox"
import "nullray:subagent"

tool_run_shell :: proc(args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	command, perr := json_arg_string(args_json, "command", allocator)
	if perr != "" {
		return "", perr
	}
	defer delete(command)

	allowed, reason := shell_command_allowed(command, allocator)
	if !allowed {
		return "", reason
	}
	defer delete(reason)

	if shell_err := subagent.check_shell_allowed(command, allocator); len(shell_err) > 0 {
		return "", shell_err
	}

	if !sandbox.shell_allowed(sandbox.state()) {
		return "", strings.clone("shell not allowed by sandbox", allocator)
	}

	workspace, werr := resolve_cwd_jail(workspace_root(context.temp_allocator), allocator)
	if werr != "" {
		return "", werr
	}
	defer delete(workspace)

	if !sandbox.path_allowed(sandbox.state(), workspace, true) {
		return "", strings.clone("workspace path not allowed for shell", allocator)
	}

	if elevate.needs_elevate(command) {
		res := elevate.run_elevated(command, workspace, allocator)
		defer elevate.result_destroy(&res)
		return elevate.format_tool_result(res, allocator), ""
	}

	stdout_r, stdout_w, pipe_err := os.pipe()
	if pipe_err != nil {
		return "", fmt.aprintf("pipe failed: %v", pipe_err, allocator = allocator)
	}
	defer os.close(stdout_r)
	stderr_r, stderr_w, pipe_err2 := os.pipe()
	if pipe_err2 != nil {
		return "", fmt.aprintf("pipe failed: %v", pipe_err2, allocator = allocator)
	}
	defer os.close(stderr_r)

	process: os.Process
	{
		defer os.close(stdout_w)
		defer os.close(stderr_w)
		argv: [3]string
		when ODIN_OS == .Windows {
			argv = {"cmd.exe", "/C", command}
		} else {
			argv = {"/bin/sh", "-c", command}
		}
		desc := os.Process_Desc{
			working_dir = workspace,
			command = argv[:],
			stdout = stdout_w,
			stderr = stderr_w,
		}
		start_err: os.Error
		process, start_err = os.process_start(desc)
		if start_err != nil {
			return "", fmt.aprintf("exec failed: %v", start_err, allocator = allocator)
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

	out: strings.Builder
	strings.builder_init(&out, allocator)
	if timed_out {
		strings.write_string(&out, "timeout\n")
	}
	if state.exited {
		strings.write_string(&out, fmt.aprintf("exit_code=%d\n", state.exit_code, allocator = allocator))
	}
	if len(stdout_b) > 0 {
		strings.write_string(&out, string(stdout_b[:]))
	}
	if len(stderr_b) > 0 {
		if len(stdout_b) > 0 {
			strings.write_string(&out, "\n")
		}
		strings.write_string(&out, string(stderr_b[:]))
	}
	return strings.to_string(out), ""
}
