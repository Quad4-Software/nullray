// SPDX-License-Identifier: 0BSD
/*
Subprocess runner for Git and Fossil commands.
*/

package vcs

import "core:fmt"
import "core:io"
import "core:os"
import "core:strings"
import "core:time"

@(private)
run :: proc(repo: Repo, argv: []string, allocator := context.allocator) -> (out: string, err: string) {
	stdout_r, stdout_w, pipe_err := os.pipe()
	if pipe_err != nil {
		return "", fmt.aprintf("VCS pipe failed: %v", pipe_err, allocator = allocator)
	}
	defer os.close(stdout_r)
	stderr_r, stderr_w, pipe_err2 := os.pipe()
	if pipe_err2 != nil {
		return "", fmt.aprintf("VCS pipe failed: %v", pipe_err2, allocator = allocator)
	}
	defer os.close(stderr_r)

	process: os.Process
	{
		defer os.close(stdout_w)
		defer os.close(stderr_w)
		desc := os.Process_Desc{
			working_dir = repo.root,
			command = argv,
			stdout = stdout_w,
			stderr = stderr_w,
		}
		start_err: os.Error
		process, start_err = os.process_start(desc)
		if start_err != nil {
			return "", fmt.aprintf("VCS exec failed: %v", start_err, allocator = allocator)
		}
	}

	stdout_b := make([dynamic]byte, context.temp_allocator)
	stderr_b := make([dynamic]byte, context.temp_allocator)
	buf: [2048]u8
	start := time.now()
	timed_out := false
	exited := false
	exit_code := 0
	for !exited {
		has_stdout, _ := os.pipe_has_data(stdout_r)
		if has_stdout {
			n, _ := os.read(stdout_r, buf[:])
			if n > 0 {
				append(&stdout_b, ..buf[:n])
			}
		}
		has_stderr, _ := os.pipe_has_data(stderr_r)
		if has_stderr {
			n, _ := os.read(stderr_r, buf[:])
			if n > 0 {
				append(&stderr_b, ..buf[:n])
			}
		}
		state, wait_err := os.process_wait(process, 0)
		if wait_err == nil && state.exited {
			exited = true
			exit_code = state.exit_code
			break
		}
		if time.since(start) >= time.Second * 30 {
			timed_out = true
			_ = os.process_kill(process)
			state, _ = os.process_wait(process)
			exited = true
			exit_code = state.exit_code
		}
	}
	for {
		n, rerr := os.read(stdout_r, buf[:])
		if n > 0 {
			append(&stdout_b, ..buf[:n])
		}
		if n == 0 || rerr == io.Error.EOF || rerr == os.General_Error.Broken_Pipe {
			break
		}
	}
	for {
		n, rerr := os.read(stderr_r, buf[:])
		if n > 0 {
			append(&stderr_b, ..buf[:n])
		}
		if n == 0 || rerr == io.Error.EOF || rerr == os.General_Error.Broken_Pipe {
			break
		}
	}
	combined := fmt.aprintf("%s%s", string(stdout_b[:]), string(stderr_b[:]), allocator = allocator)
	if timed_out {
		return combined, strings.clone("VCS command timed out", allocator)
	}
	if exit_code != 0 {
		return combined, fmt.aprintf("VCS command failed with exit %d: %s", exit_code, combined, allocator = allocator)
	}
	return combined, ""
}
