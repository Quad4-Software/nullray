// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
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
import "nullray:http"

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
Head+tail output splice: keeps the first 60% of max_out and the last 40%,
dropping the middle so exit lines and tracebacks at the tail survive. When
the middle was dropped, splice_emit writes a "\n[truncated N bytes]\n"
marker carrying the dropped count between head and tail.
*/
@(private)
Output_Splice :: struct {
	head:     [dynamic]byte,
	tail:     []byte,
	tail_len: int,
	tail_pos: int,
	seen:     int,
	head_cap: int,
	tail_cap: int,
}

@(private)
splice_init :: proc(max_out: int) -> (s: Output_Splice) {
	s.head_cap = max_out * 6 / 10
	s.tail_cap = max_out - s.head_cap
	s.head.allocator = context.temp_allocator
	if s.tail_cap > 0 {
		s.tail = make([]byte, s.tail_cap, context.temp_allocator)
	}
	return
}

// Push bytes into the splice: head fills first, overflow lands in the tail ring.
@(private)
splice_push :: proc(s: ^Output_Splice, data: []byte) {
	s.seen += len(data)
	rest := data
	if len(s.head) < s.head_cap {
		take := min(s.head_cap - len(s.head), len(rest))
		append(&s.head, ..rest[:take])
		rest = rest[take:]
	}
	if s.tail_cap == 0 || len(rest) == 0 {
		return
	}
	if len(rest) >= s.tail_cap {
		// Only the final tail_cap bytes can survive.
		copy(s.tail, rest[len(rest) - s.tail_cap:])
		s.tail_pos = 0
		s.tail_len = s.tail_cap
		return
	}
	first := min(len(rest), s.tail_cap - s.tail_pos)
	copy(s.tail[s.tail_pos:], rest[:first])
	if first < len(rest) {
		copy(s.tail, rest[first:])
	}
	s.tail_pos = (s.tail_pos + len(rest)) % s.tail_cap
	s.tail_len = min(s.tail_cap, s.tail_len + len(rest))
}

/*
Per-call drain budget: pipe_has_data loops can be kept alive forever by a
flooding writer, so every drain returns after this many bytes and lets the
outer loop re-check timeout and cancel.
*/
SHELL_DRAIN_BUDGET :: 64 * 1024

// Emit head, a dropped-count marker when the middle was cut, then the tail.
@(private)
splice_emit :: proc(s: ^Output_Splice, out: ^strings.Builder) {
	if len(s.head) > 0 {
		strings.write_string(out, string(s.head[:]))
	}
	dropped := s.seen - len(s.head) - s.tail_len
	if dropped > 0 {
		fmt.sbprintf(out, "\n[truncated %d bytes]\n", dropped)
	}
	if s.tail_len == 0 {
		return
	}
	if s.tail_len < s.tail_cap {
		// Ring never wrapped: oldest byte sits at index 0.
		strings.write_string(out, string(s.tail[:s.tail_len]))
		return
	}
	strings.write_string(out, string(s.tail[s.tail_pos:]))
	strings.write_string(out, string(s.tail[:s.tail_pos]))
}

/*
Bounded non-blocking drain for the post-exit path: the child is dead so its
bytes are already kernel-buffered, but a detached grandchild may still hold
the write end open. Read only what pipe_has_data reports ready, capped by
SHELL_DRAIN_BUDGET, so a surviving writer cannot wedge us on a blocking read
or keep has_data true forever.
*/
@(private)
drain_ready :: proc(r: ^os.File, s: ^Output_Splice, buf: []u8) {
	left := SHELL_DRAIN_BUDGET
	for left > 0 {
		has_data, _ := os.pipe_has_data(r)
		if !has_data {
			return
		}
		n, rerr := os.read(r, buf)
		if n > 0 {
			splice_push(s, buf[:n])
			left -= n
		}
		if n == 0 || rerr == io.Error.EOF || rerr == os.General_Error.Broken_Pipe {
			return
		}
	}
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
	env: []string = nil,
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
			env = env,
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
	shell_register_active(process)
	defer shell_clear_active(process)

	max_out := constants.MAX_SHELL_OUTPUT_BYTES
	stdout_s := splice_init(max_out)
	stderr_s := splice_init(max_out)
	buf: [1024]u8

	timeout := time.Millisecond * time.Duration(timeout_ms)
	start := time.now()
	stdout_done := false
	stderr_done := false
	timed_out := false
	state: os.Process_State

	for !stdout_done || !stderr_done {
		if http.cancel_requested() {
			timed_out = true
			shell_kill_process_tree(process)
			break
		}
		if time.since(start) >= timeout {
			timed_out = true
			shell_kill_process_tree(process)
			break
		}

		got_data := false
		if !stdout_done {
			has_data, read_err := os.pipe_has_data(stdout_r)
			if has_data {
				n, rerr := os.read(stdout_r, buf[:])
				if n > 0 {
					got_data = true
					splice_push(&stdout_s, buf[:n])
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
					got_data = true
					splice_push(&stderr_s, buf[:n])
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
			// The non-blocking wait reaps a finished child on Linux
			// (waitid WEXITED without WNOWAIT at reap time), so keep this
			// state: re-waiting below would hit ECHILD and fabricate
			// exit_code=1 plus "process status unavailable".
			state = wait_state
			// Child exited; drain only what is already buffered. A detached
			// grandchild holding a write end must not turn this into a
			// blocking read past the timeout.
			drain_ready(stdout_r, &stdout_s, buf[:])
			drain_ready(stderr_r, &stderr_s, buf[:])
			stdout_done = true
			stderr_done = true
			break
		}
		if !got_data {
			// Quiet child: avoid a busy spin on poll+waitid.
			time.sleep(2 * time.Millisecond)
		}
	}

	if !state.exited {
		// Timeout and cancel already fired the kill; a pipes-EOF exit with
		// the child still running (it redirected its streams) leaves a
		// blocking wait unbounded. Kill the tree first so the wait is
		// bounded either way; a second kill is a harmless no-op.
		shell_kill_process_tree(process)
		state, _ = os.process_wait(process)
	}

	out: strings.Builder
	strings.builder_init(&out, allocator)
	if timed_out {
		strings.write_string(&out, "timeout\n")
	}
	if state.exited {
		fmt.sbprintf(&out, "exit_code=%d\n", state.exit_code)
	} else {
		// Always emit a trailer so verify and callers fail closed on missing status.
		strings.write_string(&out, "exit_code=1\n")
		strings.write_string(&out, "process status unavailable\n")
	}
	if stdout_s.seen > 0 {
		splice_emit(&stdout_s, &out)
	}
	if stderr_s.seen > 0 {
		if stdout_s.seen > 0 {
			strings.write_string(&out, "\n")
		}
		splice_emit(&stderr_s, &out)
	}
	return strings.to_string(out), ""
}
