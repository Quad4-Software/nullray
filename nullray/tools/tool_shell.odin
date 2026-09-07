// SPDX-License-Identifier: 0BSD
/*
run_shell tool: execute /bin/sh -c in workspace when sandbox permits.
*/

package tools

import "core:fmt"
import "core:os"
import "core:strings"
import "nullray:elevate"
import "nullray:sandbox"
import "nullray:subagent"

tool_run_shell :: proc(args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	command, perr := json_arg_string(args_json, "command", allocator)
	if perr != "" {
		return "", perr
	}
	defer delete(command)

	timeout_ms, terr := shell_timeout_ms_from_args(args_json, allocator)
	if terr != "" {
		return "", terr
	}

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

	argv: [3]string
	when ODIN_OS == .Windows {
		argv = {"cmd.exe", "/C", command}
	} else {
		argv = {"/bin/sh", "-c", command}
	}
	return run_process_capture(argv[:], workspace, timeout_ms, allocator)
}
