// SPDX-License-Identifier: 0BSD
/*
Shared shell timeout resolution and process capture for run_shell / run_script.
*/

package tools

import "core:fmt"
import "core:io"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:time"
import "nullray:constants"

shell_timeout_ms_default :: proc() -> int {
	if raw, ok := os.lookup_env(constants.ENV_SHELL_TIMEOUT_MS, context.temp_allocator); ok {
		if n, parsed := strconv.parse_int(strings.trim_space(raw)); parsed && n > 0 {
			if n > constants.MAX_SHELL_TIMEOUT_MS {
				return constants.MAX_SHELL_TIMEOUT_MS
			}
			return n
		}
	}
	if auto_env_truthy(constants.ENV_AUTO) {
		return constants.AUTO_SHELL_TIMEOUT_MS
	}
	return constants.SHELL_TIMEOUT_MS
}

shell_timeout_ms_from_args :: proc(args_json: string, allocator := context.allocator) -> (int, string) {
	timeout_ms := shell_timeout_ms_default()
	if raw, tok := json_arg_string_optional(args_json, "timeout_ms", "", allocator); tok == "" && len(raw) > 0 {
		defer delete(raw)
		if n, n_ok := strconv.parse_int(strings.trim_space(raw)); n_ok && n > 0 {
			timeout_ms = n
			if timeout_ms > constants.MAX_SHELL_TIMEOUT_MS {
				timeout_ms = constants.MAX_SHELL_TIMEOUT_MS
			}
		}
	} else if tok != "" {
		return 0, tok
	}
	return timeout_ms, ""
}

@(private)
auto_env_truthy :: proc(key: string) -> bool {
	v, ok := os.lookup_env(key, context.temp_allocator)
	if !ok {
		return false
	}
	switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
	case "1", "true", "yes", "on":
		return true
	}
	return false
}

/*
Run command, capture stdout/stderr up to max bytes, honor timeout_ms.
On timeout kills the process tree via platform helper.
*/
run_process_capture :: proc(
	command: []string,
	workspace: string,
	timeout_ms: int,
	allocator := context.allocator,
) -> (result: string, err: string) {
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
		desc := os.Process_Desc{
			working_dir = workspace,
			command = command,
			stdout = stdout_w,
			stderr = stderr_w,
		}
		start_err: os.Error
		process, start_err = os.process_start(desc)
		if start_err != nil {
			return "", fmt.aprintf("exec failed: %v", start_err, allocator = allocator)
		}
	}
	shell_claim_process_group(process)

	stdout_b: [dynamic]byte
	stdout_b.allocator = context.temp_allocator
	stderr_b: [dynamic]byte
	stderr_b.allocator = context.temp_allocator
	buf: [1024]u8

	max_out := constants.MAX_SHELL_OUTPUT_BYTES
	timeout := time.Millisecond * time.Duration(timeout_ms)
	start := time.now()
	stdout_done := false
	stderr_done := false
	timed_out := false
	stdout_trunc := false
	stderr_trunc := false

	for !stdout_done || !stderr_done {
		if time.since(start) >= timeout {
			timed_out = true
			shell_kill_process_tree(process)
			break
		}

		if !stdout_done {
			has_data, read_err := os.pipe_has_data(stdout_r)
			if has_data {
				n, rerr := os.read(stdout_r, buf[:])
				if n > 0 {
					if len(stdout_b) < max_out {
						remain := max_out - len(stdout_b)
						take := n
						if take > remain {
							take = remain
							stdout_trunc = true
						}
						append(&stdout_b, ..buf[:take])
					} else {
						stdout_trunc = true
					}
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
				if n > 0 {
					if len(stderr_b) < max_out {
						remain := max_out - len(stderr_b)
						take := n
						if take > remain {
							take = remain
							stderr_trunc = true
						}
						append(&stderr_b, ..buf[:take])
					} else {
						stderr_trunc = true
					}
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
				if n > 0 {
					if len(stdout_b) < max_out {
						remain := max_out - len(stdout_b)
						take := n
						if take > remain {
							take = remain
							stdout_trunc = true
						}
						append(&stdout_b, ..buf[:take])
					} else {
						stdout_trunc = true
					}
				}
				if n == 0 || rerr == io.Error.EOF || rerr == os.General_Error.Broken_Pipe {
					stdout_done = true
				}
			}
			for !stderr_done {
				n, rerr := os.read(stderr_r, buf[:])
				if n > 0 {
					if len(stderr_b) < max_out {
						remain := max_out - len(stderr_b)
						take := n
						if take > remain {
							take = remain
							stderr_trunc = true
						}
						append(&stderr_b, ..buf[:take])
					} else {
						stderr_trunc = true
					}
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
		shell_kill_process_tree(process)
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
	if stdout_trunc || stderr_trunc {
		strings.write_string(&out, "\n[truncated shell output]\n")
	}
	return strings.to_string(out), ""
}
