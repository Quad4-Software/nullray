// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Script tool execution: spawn under interpreter, JSON args on stdin,
stdout to result, timeout and stderr capture.
*/

package tools

import "core:fmt"
import "core:os"
import "core:strings"
import "core:thread"
import "core:time"
import "nullray:constants"
import "nullray:sandbox"
import "nullray:subagent"


@(private)
script_tool_env :: proc(args_json: string, allocator := context.allocator) -> []string {
	out := make([dynamic]string, allocator)
	// toolchain_shell_env already carries the base environ when enabled.
	base := sandbox.toolchain_shell_env(allocator)
	if base == nil {
		if env, eerr := os.environ(allocator); eerr == nil {
			base = env
		}
	}
	old_path := ""
	for e in base {
		if strings.has_prefix(e, "PATH=") {
			old_path = e[5:]
		}
	}
	for e in base {
		if strings.has_prefix(e, "NULLRAY_TOOL_ARGS=") || strings.has_prefix(e, "PATH=") {
			continue
		}
		append(&out, e)
	}
	// System dirs first: sandboxed exec into ungranted home dirs fails
	// (see hooks hook_env). User PATH entries remain reachable at the tail.
	append(&out, strings.concatenate({"PATH=/usr/local/bin:/usr/bin:/bin", len(old_path) > 0 ? ":" : "", old_path}, allocator))
	append(&out, strings.concatenate({"NULLRAY_TOOL_ARGS=", args_json}, allocator))
	return out[:]
}

// Tool.run_named entry point.
@(private)
script_tool_exec :: proc(
	user: rawptr,
	name: string,
	args_json: string,
	allocator := context.allocator,
) -> (result: string, err: string) {
	st := cast(^Script_Tool)user
	if st == nil {
		return "", strings.clone("script tool missing binding", allocator)
	}
	_ = name

	// Script tools are user code: kind .Shell goes through the same shell
	// permission gate as run_shell (perms ask/allow/yolo, deny lists).
	if st.kind == .Shell {
		probe := st.path
		if len(st.interp) > 0 {
			probe = fmt.aprintf("%s %s", st.interp, st.path, allocator = context.temp_allocator)
		}
		allowed, reason := shell_command_allowed(probe, allocator)
		if !allowed {
			return "", reason
		}
		delete(reason, allocator)
	}
	if shell_err := subagent.check_shell_allowed(st.path, allocator); len(shell_err) > 0 {
		return "", shell_err
	}
	if !sandbox.shell_allowed(sandbox.state()) {
		return "", strings.clone("shell not allowed by sandbox", allocator)
	}
	workspace, werr := resolve_cwd_jail(workspace_root(context.temp_allocator), allocator)
	if werr != "" {
		return "", werr
	}
	defer delete(workspace, allocator)
	if !sandbox.path_allowed(sandbox.state(), workspace, true) {
		return "", strings.clone("workspace path not allowed for shell", allocator)
	}

	argv := make([dynamic]string, context.temp_allocator)
	if len(st.interp) > 0 {
		append(&argv, st.interp)
	}
	append(&argv, st.path)
	env := script_tool_env(args_json, context.temp_allocator)
	return script_tool_run_capture(argv[:], workspace, args_json, env, allocator)
}

@(private)
Script_Stdin :: struct {
	w:     ^os.File,
	input: string,
}

// Feeds args JSON on a thread so a script that never reads stdin cannot
// deadlock the caller, killing the child breaks the pipe.
@(private)
script_stdin_proc :: proc(data: rawptr) {
	w := cast(^Script_Stdin)data
	// Loop short writes, any error (EPIPE once the read end is gone) just
	// stops the feed.
	rest := transmute([]u8)w.input
	for len(rest) > 0 {
		n, werr := os.write(w.w, rest)
		if n <= 0 || werr != nil {
			break
		}
		rest = rest[n:]
	}
	_ = os.close(w.w)
}

/*
Spawn the script with args JSON on stdin, capture stdout/stderr bounded by
MAX_SHELL_OUTPUT_BYTES, kill on timeout. Mirrors run_process_capture but adds
the stdin feed and the stderr-only-on-failure suffix rule.
*/
@(private)
script_tool_run_capture :: proc(
	argv: []string,
	workspace: string,
	input: string,
	env: []string,
	allocator := context.allocator,
) -> (result: string, err: string) {
	stdin_r, stdin_w, perr0 := os.pipe()
	if perr0 != nil {
		return "", fmt.aprintf("pipe failed: %v", perr0, allocator = allocator)
	}
	stdin_r_open := true
	defer {
		if stdin_r_open {
			os.close(stdin_r)
		}
	}
	stdout_r, stdout_w, perr1 := os.pipe()
	if perr1 != nil {
		os.close(stdin_w)
		return "", fmt.aprintf("pipe failed: %v", perr1, allocator = allocator)
	}
	defer os.close(stdout_r)
	stderr_r, stderr_w, perr2 := os.pipe()
	if perr2 != nil {
		os.close(stdin_w)
		os.close(stdout_w)
		return "", fmt.aprintf("pipe failed: %v", perr2, allocator = allocator)
	}
	defer os.close(stderr_r)

	process: os.Process
	writer: Script_Stdin
	wth: ^thread.Thread
	{
		defer os.close(stdout_w)
		defer os.close(stderr_w)
		desc := os.Process_Desc{
			working_dir = workspace,
			command = argv,
			env = env,
			stdin = stdin_r,
			stdout = stdout_w,
			stderr = stderr_w,
		}
		start_err: os.Error
		process, start_err = os.process_start(desc)
		// The child holds its own dup of stdin_r, keeping the parent copy
		// open would leave the pipe readable forever, so a blocked stdin
		// writer would never see EPIPE after the tree is killed.
		os.close(stdin_r)
		stdin_r_open = false
		if start_err != nil {
			os.close(stdin_w)
			return "", fmt.aprintf("exec failed: %v", start_err, allocator = allocator)
		}
		writer = Script_Stdin{w = stdin_w, input = input}
		wth = thread.create_and_start_with_data(&writer, script_stdin_proc)
		if wth == nil {
			os.close(stdin_w)
		}
	}
	shell_claim_process_group(process)
	shell_register_active(process)
	defer shell_clear_active(process)

	stdout_b: [dynamic]u8
	stdout_b.allocator = context.temp_allocator
	stderr_b: [dynamic]u8
	stderr_b.allocator = context.temp_allocator
	buf: [4096]u8
	max_out := constants.MAX_SHELL_OUTPUT_BYTES
	timeout := time.Millisecond * time.Duration(SCRIPT_TOOL_TIMEOUT_MS)
	start := time.now()
	stdout_done := false
	stderr_done := false
	timed_out := false
	// The non-blocking process_wait peek REAPS a finished child (it returns a
	// real exit state), so a later blocking wait hits ECHILD. Capture the
	// exit state here, in the loop, instead of re-waiting afterwards.
	exited := false
	exit_code := 0

	for !stdout_done || !stderr_done {
		if time.since(start) >= timeout {
			timed_out = true
			shell_kill_process_tree(process)
			break
		}
		if !stdout_done {
			stdout_done = script_drain(stdout_r, &stdout_b, buf[:], max_out)
		}
		if !stderr_done {
			stderr_done = script_drain(stderr_r, &stderr_b, buf[:], max_out)
		}
		state, werr := os.process_wait(process, 0)
		if werr == nil && state.exited {
			exited = true
			exit_code = state.exit_code
			// Child is dead so all its bytes are already kernel-buffered,
			// drain what is ready and stop instead of blocking on EOF that a
			// detached grandchild holding the write end could postpone.
			_ = script_drain(stdout_r, &stdout_b, buf[:], max_out)
			_ = script_drain(stderr_r, &stderr_b, buf[:], max_out)
			break
		}
		time.sleep(2 * time.Millisecond)
	}
	if !exited {
		// The timeout path already fired the kill, a pipes-EOF exit with
		// the child still running leaves a blocking wait unbounded. Kill
		// the tree first so the wait is bounded either way.
		shell_kill_process_tree(process)
		state, _ := os.process_wait(process)
		if state.exited {
			exited = true
			exit_code = state.exit_code
		}
	}
	if wth != nil {
		thread.join(wth)
		thread.destroy(wth)
	}

	out: strings.Builder
	strings.builder_init(&out, allocator)
	failed := timed_out || !exited || exit_code != 0
	if timed_out {
		strings.write_string(&out, "timeout\n")
	}
	if exited && exit_code != 0 {
		fmt.sbprintf(&out, "exit_code=%d\n", exit_code)
	}
	if !exited {
		strings.write_string(&out, "process status unavailable\n")
	}
	if len(stdout_b) > 0 {
		strings.write_string(&out, string(stdout_b[:]))
	}
	if failed && len(stderr_b) > 0 {
		if len(stdout_b) > 0 {
			strings.write_string(&out, "\n")
		}
		strings.write_string(&out, "stderr: ")
		strings.write_string(&out, string(stderr_b[:]))
	}
	return strings.to_string(out), ""
}

/*
Drain currently buffered pipe bytes, at most SHELL_DRAIN_BUDGET per call so
a flooding writer cannot starve the outer loop's timeout check. Returns
true only on EOF or error, false just means the pipe is momentarily empty
or the budget ran out.
*/
@(private)
script_drain :: proc(r: ^os.File, b: ^[dynamic]u8, buf: []u8, cap: int) -> bool {
	left := SHELL_DRAIN_BUDGET
	for left > 0 {
		has_data, _ := os.pipe_has_data(r)
		if !has_data {
			return false
		}
		n, rd_err := os.read(r, buf)
		if n > 0 {
			left -= n
		}
		if n > 0 && len(b^) < cap {
			remain := cap - len(b^)
			take := n
			if take > remain {
				take = remain
			}
			append(b, ..buf[:take])
		}
		if n == 0 || rd_err != nil {
			return true
		}
	}
	return false
}
