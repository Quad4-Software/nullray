// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Hook command execution, stdout capture, and output parsing.
*/

package hooks

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"
import "nullray:constants"
import "nullray:crash"

apply_hook_output :: proc(event: Event, stdout: string, res: ^Result, allocator := context.allocator) {
	if len(res.decision) > 0 || len(res.rewrite_args) > 0 {
		return
	}
	rest := stdout
	for line in strings.split_lines_iterator(&rest) {
		trimmed := strings.trim_space(line)
		if len(trimmed) == 0 || trimmed[0] != '{' {
			continue
		}
		v, perr := json.parse_string(trimmed, .JSON, allocator = context.temp_allocator)
		if perr != nil {
			continue
		}
		obj, is_obj := v.(json.Object)
		if !is_obj {
			continue
		}
		if event == .PreToolUse {
			if rv, rok := obj["rewrite"]; rok {
				if _, rw_obj := rv.(json.Object); rw_obj {
					if s, uerr := json.unparse(rv, allocator = allocator); uerr == nil {
						res.rewrite_args = s
						return
					}
				}
			}
		}
		ds, has_decision := obj["decision"].(json.String)
		if !has_decision {
			continue
		}
		switch string(ds) {
		case "allow":
			if event == .PermissionRequest {
				res.decision = strings.clone("allow", allocator)
				return
			}
		case "deny":
			if event == .PermissionRequest {
				res.decision = strings.clone("deny", allocator)
				if rs, rok := obj["reason"].(json.String); rok {
					res.reason = strings.clone(string(rs), allocator)
				}
				return
			}
		case "rewrite":
			if event == .PreToolUse {
				if av, aok := obj["args"]; aok {
					if _, args_obj := av.(json.Object); args_obj {
						if s, uerr := json.unparse(av, allocator = allocator); uerr == nil {
							res.rewrite_args = s
							return
						}
					}
				}
			}
		}
	}
}

@(private)
timeout_ms :: proc() -> int {
	if v, ok := os.lookup_env(constants.ENV_HOOK_TIMEOUT_MS, context.temp_allocator); ok {
		if n, nok := strconv.parse_int(v); nok && n > 0 {
			return n
		}
	}
	return 5_000
}

@(private)
Hook_Writer :: struct {
	w:     ^os.File,
	input: string,
}

// Feeds hook stdin from a thread so a child that never reads stdin cannot
// deadlock the caller past its timeout. Killing the child breaks the pipe.
@(private)
hook_writer_proc :: proc(data: rawptr) {
	w := cast(^Hook_Writer)data
	// Loop short writes; any error (EPIPE once the read end is gone) just
	// stops the feed.
	rest := transmute([]u8)w.input
	for len(rest) > 0 {
		n, werr := os.write(w.w, rest)
		if n <= 0 || werr != nil {
			break
		}
		rest = rest[n:]
	}
	// Close the write end so commands reading stdin to EOF finish.
	_ = os.close(w.w)
}

// Hook stdout is captured so decision/rewrite JSON lines can be read back.
// The drain happens inside the wait loop: a hook that prints more than the
// pipe buffer would otherwise block before exiting.
@(private)
HOOK_STDOUT_CAP :: 64 * 1024

// Per-call drain budget: a flooding writer can keep pipe_has_data true
// forever, so each call returns after this many bytes and lets the outer
// loop re-check the timeout.
@(private)
HOOK_DRAIN_BUDGET :: 64 * 1024

// Non-blocking drain: returns when no data is ready, the byte budget is
// spent, or the pipe hit EOF.
@(private)
drain_hook_stdout :: proc(r: ^os.File, b: ^[dynamic]u8, buf: []u8) {
	left := HOOK_DRAIN_BUDGET
	for left > 0 {
		has_data, _ := os.pipe_has_data(r)
		if !has_data {
			return
		}
		n, rd_err := os.read(r, buf)
		if n > 0 {
			left -= n
		}
		if n > 0 && len(b^) < HOOK_STDOUT_CAP {
			remain := HOOK_STDOUT_CAP - len(b^)
			take := n
			if take > remain {
				take = remain
			}
			append(b, ..buf[:take])
		}
		if n == 0 || rd_err != nil {
			return
		}
	}
}

// Hook and script-tool children inherit the user env but put system dirs
// first on PATH: under the sandbox, PATH entries inside home (cargo shim
// dirs, ~/.local/bin) resolve to ungranted paths and silently fail exec
// with exit 126. User dirs stay reachable at the tail of PATH.
hook_env :: proc(allocator := context.temp_allocator) -> []string {
	base, eerr := os.environ(context.temp_allocator)
	if eerr != nil {
		base = nil
	}
	out := make([dynamic]string, allocator)
	for e in base {
		if strings.has_prefix(e, "PATH=") {
			continue
		}
		append(&out, e)
	}
	old_path := ""
	for e in base {
		if strings.has_prefix(e, "PATH=") {
			old_path = e[5:]
		}
	}
	new_path := strings.concatenate({"PATH=/usr/local/bin:/usr/bin:/bin", len(old_path) > 0 ? ":" : "", old_path}, allocator)
	append(&out, new_path)
	return out[:]
}

@(private)
run_command :: proc(command, input: string) -> (exit_code: int, timed_out: bool, output: string, err: string) {
	stdin_r, stdin_w, perr := os.pipe()
	if perr != nil {
		return 0, false, "", fmt.tprintf("hook pipe failed: %v", perr)
	}
	stdin_r_open := true
	defer {
		if stdin_r_open {
			os.close(stdin_r)
		}
	}
	stdout_r, stdout_w, perr2 := os.pipe()
	if perr2 != nil {
		os.close(stdin_w)
		return 0, false, "", fmt.tprintf("hook pipe failed: %v", perr2)
	}
	defer os.close(stdout_r)
	process: os.Process
	writer: Hook_Writer
	wth: ^thread.Thread
	{
		defer os.close(stdout_w)
		argv: [3]string
		when ODIN_OS == .Windows {
			argv = {"cmd.exe", "/C", command}
		} else {
			argv = {"/bin/sh", "-c", command}
		}
		desc := os.Process_Desc{
			command = argv[:],
			stdin = stdin_r,
			stdout = stdout_w,
			env = hook_env(),
		}
		start_err: os.Error
		process, start_err = os.process_start(desc)
		// The child holds its own dup of stdin_r; keeping the parent copy
		// open would leave the pipe readable forever, so a blocked stdin
		// writer would never see EPIPE after the tree is killed.
		os.close(stdin_r)
		stdin_r_open = false
		if start_err != nil {
			crash.logf("hook exec failed: %v", start_err)
			os.close(stdin_w)
			return 0, false, "", fmt.tprintf("hook exec failed: %v", start_err)
		}
		// Own process group so a timeout kill reaches grandchildren; a
		// survivor holding stdin would otherwise wedge the writer join.
		hook_claim_process_group(process)
		writer = Hook_Writer{w = stdin_w, input = input}
		wth = thread.create_and_start_with_data(&writer, hook_writer_proc)
		if wth == nil {
			os.close(stdin_w)
		}
	}
	// Join the writer before closing the parent write end, and only after the
	// child exits or is killed (a dead child makes any blocked write fail).
	exit_code = 0
	stdout_b: [dynamic]u8
	stdout_b.allocator = context.temp_allocator
	buf: [4096]u8
	start := time.now()
	for {
		drain_hook_stdout(stdout_r, &stdout_b, buf[:])
		state, wait_err := os.process_wait(process, 0)
		if wait_err == nil && state.exited {
			exit_code = state.exit_code
			break
		}
		if time.since(start) >= time.Millisecond * time.Duration(timeout_ms()) {
			hook_kill_process_tree(process)
			state, _ = os.process_wait(process)
			exit_code = state.exit_code if state.exited else 1
			timed_out = true
			break
		}
		time.sleep(2 * time.Millisecond)
	}
	// Final drain: anything written between the last poll and exit. Stays
	// non-blocking so a detached grandchild holding the pipe cannot wedge us.
	drain_hook_stdout(stdout_r, &stdout_b, buf[:])
	if wth != nil {
		thread.join(wth)
		thread.destroy(wth)
	}
	return exit_code, timed_out, string(stdout_b[:]), ""
}
