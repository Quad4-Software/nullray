/*
run_script tool: write code to a temp script file and execute with optional bwrap sandbox.
*/

package tools

import "core:fmt"
import "core:io"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:strings"
import "core:time"
import "nullray:constants"
import "nullray:sandbox"

SCRIPT_TMP_DIR :: ".nullray-tmp"

bwrap_available :: proc() -> bool {
	when ODIN_OS == .Windows {
		return false
	} else {
		path_env, ok := os.lookup_env("PATH", context.temp_allocator)
		if !ok {
			return false
		}
		path_copy := path_env
		for dir in strings.split_iterator(&path_copy, ":") {
			if len(dir) == 0 {
				continue
			}
			candidate, jerr := filepath.join({dir, "bwrap"}, context.temp_allocator)
			if jerr != nil {
				continue
			}
			if os.exists(candidate) {
				return true
			}
		}
		return false
	}
}

@(private)
script_language :: proc(language: string) -> (interpreter: string, ext: string, ok: bool) {
	switch strings.to_lower(strings.trim_space(language), context.temp_allocator) {
	case "sh", "bash":
		when ODIN_OS == .Windows {
			return "bash.exe", ".sh", true
		} else {
			return "/bin/sh", ".sh", true
		}
	case "python", "python3":
		when ODIN_OS == .Windows {
			return "python", ".py", true
		} else {
			return "/usr/bin/python3", ".py", true
		}
	}
	return "", "", false
}

@(private)
script_tmp_dir :: proc(workspace: string, allocator := context.allocator) -> (dir: string, err: string) {
	joined, jerr := filepath.join({workspace, SCRIPT_TMP_DIR}, allocator)
	if jerr != nil {
		return "", fmt.aprintf("tmp path failed: %v", jerr, allocator = allocator)
	}
	if mkerr := os.make_directory_all(joined); mkerr != nil {
		return "", fmt.aprintf("mkdir failed: %v", mkerr, allocator = allocator)
	}
	return joined, ""
}

@(private)
build_bwrap_command :: proc(
	workspace: string,
	interpreter: string,
	script_path: string,
	allocator := context.allocator,
) -> []string {
	args := make([dynamic]string, allocator)
	append(&args, "bwrap")
	append(&args, "--ro-bind", "/usr", "/usr")
	append(&args, "--ro-bind", "/bin", "/bin")
	append(&args, "--ro-bind", "/lib", "/lib")
	append(&args, "--ro-bind", "/lib64", "/lib64")
	append(&args, "--dev", "/dev")
	append(&args, "--proc", "/proc")
	append(&args, "--tmpfs", "/tmp")
	append(&args, "--bind", workspace, workspace)
	append(&args, "--chdir", workspace)
	append(&args, "--unshare-net")
	append(&args, "--die-with-parent")
	append(&args, "--")
	append(&args, interpreter)
	append(&args, script_path)
	return args[:]
}

@(private)
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

tool_run_script :: proc(args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	language, lerr := json_arg_string(args_json, "language", allocator)
	if lerr != "" {
		return "", lerr
	}
	defer delete(language)
	code, cerr := json_arg_string(args_json, "code", allocator)
	if cerr != "" {
		return "", cerr
	}
	defer delete(code)
	timeout_ms := constants.SHELL_TIMEOUT_MS
	if raw, tok := json_arg_string_optional(args_json, "timeout_ms", "", allocator); tok == "" && len(raw) > 0 {
		defer delete(raw)
		if n, n_ok := strconv.parse_int(raw); n_ok && n > 0 {
			timeout_ms = n
		}
	} else if tok != "" {
		return "", tok
	}

	interpreter, ext, lang_ok := script_language(language)
	if !lang_ok {
		return "", strings.clone("unsupported language (use sh, bash, python, python3)", allocator)
	}

	probe := fmt.aprintf("%s script%s", interpreter, ext, allocator = allocator)
	defer delete(probe)
	allowed, reason := shell_command_allowed(probe, allocator)
	if !allowed {
		return "", reason
	}
	defer delete(reason)

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

	tmp_dir, tderr := script_tmp_dir(workspace, allocator)
	if tderr != "" {
		return "", tderr
	}
	defer delete(tmp_dir)

	script_name := fmt.aprintf("nullray-script-%d%s", time.to_unix_seconds(time.now()), ext, allocator = allocator)
	defer delete(script_name)
	script_path, sperr := filepath.join({tmp_dir, script_name}, allocator)
	if sperr != nil {
		return "", fmt.aprintf("script path failed: %v", sperr, allocator = allocator)
	}
	defer {
		_ = os.remove(script_path)
		delete(script_path)
	}

	if !sandbox.path_allowed(sandbox.state(), script_path, true) {
		return "", strings.clone("script path not allowed for write", allocator)
	}
	if werr2 := os.write_entire_file(script_path, transmute([]u8)code); werr2 != nil {
		return "", fmt.aprintf("write script failed: %v", werr2, allocator = allocator)
	}

	command: []string
	if bwrap_available() {
		command = build_bwrap_command(workspace, interpreter, script_path, allocator)
		defer delete(command)
	} else {
		command = make([]string, 2, allocator)
		command[0] = strings.clone(interpreter, allocator)
		command[1] = strings.clone(script_path, allocator)
		defer {
			delete(command[0])
			delete(command[1])
			delete(command)
		}
	}

	return run_process_capture(command, workspace, timeout_ms, allocator)
}
