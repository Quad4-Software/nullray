// SPDX-License-Identifier: 0BSD
/*
run_script tool: write code to a temp script file and execute with optional bwrap sandbox.
*/

package tools

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"
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
	timeout_ms, terr := shell_timeout_ms_from_args(args_json, allocator)
	if terr != "" {
		return "", terr
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

	if os.write_entire_file(script_path, transmute([]u8)code) != nil {
		return "", strings.clone("write script failed", allocator)
	}
	when ODIN_OS != .Windows {
		_ = os.chmod(script_path, os.perm(0o700))
	}

	cmd: []string
	owned_cmd: [dynamic]string
	owned_cmd.allocator = context.temp_allocator
	if bwrap_available() {
		cmd = build_bwrap_command(workspace, interpreter, script_path, context.temp_allocator)
	} else {
		append(&owned_cmd, interpreter, script_path)
		cmd = owned_cmd[:]
	}
	return run_process_capture(cmd, workspace, timeout_ms, allocator)
}
