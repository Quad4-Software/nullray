// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
read_man and apropos tools. Linux uses man(1). Other OS returns a clear error.
*/

package tools

import "core:fmt"
import "core:io"
import "core:os"
import "core:strings"
import "core:time"
import "nullray:constants"
import "nullray:http"

tool_read_man :: proc(args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	when ODIN_OS != .Linux {
		return "", strings.clone("read_man requires Linux (man-db or mandoc)", allocator)
	} else {
		page, perr := json_arg_string(args_json, "page", allocator)
		if perr != "" {
			return "", perr
		}
		defer delete(page)
		section, serr := json_arg_string_optional(args_json, "section", "", allocator)
		if serr != "" {
			return "", serr
		}
		defer delete(section)
		max_chars, merr := json_arg_int_optional(args_json, "max_chars", constants.MAX_MAN_PAGE_CHARS, allocator)
		if merr != "" {
			return "", merr
		}
		if max_chars <= 0 {
			max_chars = constants.MAX_MAN_PAGE_CHARS
		}
		pname := strings.trim_space(page)
		if len(pname) == 0 || strings.contains(pname, "/") || strings.contains(pname, "..") {
			return "", strings.clone("invalid man page name", allocator)
		}
		exe, ok := find_on_path("man", context.temp_allocator)
		if !ok {
			return "", strings.clone("man not found on PATH", allocator)
		}
		argv: [dynamic]string
		argv.allocator = context.temp_allocator
		append(&argv, exe, "-P", "cat")
		sec := strings.trim_space(section)
		if len(sec) > 0 {
			append(&argv, sec)
		}
		append(&argv, pname)
		env := docs_man_env(context.temp_allocator)
		out, oerr := run_capture_argv_env(argv[:], env, allocator)
		if oerr != "" {
			return "", oerr
		}
		plain := strip_man_overstrike(out, context.temp_allocator)
		delete(out)
		if len(plain) == 0 {
			return "", fmt.aprintf("no man page for %s", pname, allocator = allocator)
		}
		if len(plain) > max_chars {
			head := strings.clone(plain[:max_chars], allocator)
			note := fmt.tprintf("\n\n[truncated at %d chars; re-call with max_chars or a section]", max_chars)
			return strings.concatenate({head, note}, allocator), ""
		}
		return strings.clone(plain, allocator), ""
	}
}

tool_apropos :: proc(args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	when ODIN_OS != .Linux {
		return "", strings.clone("apropos requires Linux", allocator)
	} else {
		keyword, kerr := json_arg_string(args_json, "keyword", allocator)
		if kerr != "" {
			return "", kerr
		}
		defer delete(keyword)
		kw := strings.trim_space(keyword)
		if len(kw) == 0 || strings.contains(kw, ";") || strings.contains(kw, "|") {
			return "", strings.clone("invalid apropos keyword", allocator)
		}
		// argv exec only: this is a read-only docs tool, so no shell ever
		// sees the keyword and substitution metachars stay inert.
		exe, ok := find_on_path("apropos", context.temp_allocator)
		if !ok {
			return "", strings.clone("apropos not found on PATH", allocator)
		}
		env := docs_man_env(context.temp_allocator)
		out, oerr := run_capture_argv_env([]string{exe, "-l", kw}, env, allocator)
		if oerr != "" {
			// apropos exits nonzero with "nothing appropriate" on a miss,
			// keep the friendly empty result for that case only.
			if strings.contains(oerr, "nothing appropriate") {
				delete(oerr, allocator)
				return strings.clone("(no apropos matches)", allocator), ""
			}
			return "", oerr
		}
		if len(strings.trim_space(out)) == 0 {
			delete(out)
			return strings.clone("(no apropos matches)", allocator), ""
		}
		// Apply the old "| head -n" cap in-process.
		capped := head_lines(out, constants.MAX_APROPOS_LINES, allocator)
		delete(out)
		return capped, ""
	}
}

// Keep the first max_lines newline-terminated lines of s.
@(private)
head_lines :: proc(s: string, max_lines: int, allocator := context.allocator) -> string {
	seen := 0
	for i in 0 ..< len(s) {
		if s[i] == '\n' {
			seen += 1
			if seen >= max_lines {
				return strings.clone(s[:i + 1], allocator)
			}
		}
	}
	return strings.clone(s, allocator)
}

run_capture_argv :: proc(argv: []string, allocator := context.allocator) -> (result: string, err: string) {
	return run_capture_argv_env(argv, nil, allocator)
}

/*
Bounded non-blocking drain: pulls at most SHELL_DRAIN_BUDGET bytes per call
so a flooding writer cannot keep the outer loop from re-checking timeout
and cancel. Returns true on EOF or read error, sets truncated^ when bytes
had to be dropped past max_out.
*/
@(private)
docs_pipe_drain :: proc(r: ^os.File, b: ^[dynamic]byte, buf: []u8, max_out: int, truncated: ^bool) -> bool {
	left := SHELL_DRAIN_BUDGET
	for left > 0 {
		has_data, _ := os.pipe_has_data(r)
		if !has_data {
			return false
		}
		n, rerr := os.read(r, buf)
		if n > 0 {
			left -= n
			if len(b^) < max_out {
				take := min(n, max_out - len(b^))
				append(b, ..buf[:take])
				if take < n {
					truncated^ = true
				}
			} else {
				truncated^ = true
			}
		}
		if n == 0 || rerr == io.Error.EOF || rerr == os.General_Error.Broken_Pipe {
			return true
		}
	}
	return false
}

@(private)
docs_man_env :: proc(allocator := context.allocator) -> []string {
	out := make([dynamic]string, allocator)
	append(&out, "MANPAGER=cat", "PAGER=cat", "MANROFFSEQ=", "MANWIDTH=100", "LC_ALL=C")
	if path, ok := os.lookup_env("PATH", context.temp_allocator); ok && len(path) > 0 {
		append(&out, fmt.aprintf("PATH=%s", path, allocator = allocator))
	} else {
		append(&out, "PATH=/usr/bin:/bin")
	}
	if mpath, ok := os.lookup_env("MANPATH", context.temp_allocator); ok && len(mpath) > 0 {
		append(&out, fmt.aprintf("MANPATH=%s", mpath, allocator = allocator))
	}
	return out[:]
}

run_capture_argv_env :: proc(argv: []string, env: []string, allocator := context.allocator) -> (result: string, err: string) {
	if len(argv) == 0 {
		return "", strings.clone("empty command", allocator)
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
		desc := os.Process_Desc{
			command = argv,
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

	stdout_b: [dynamic]byte
	stdout_b.allocator = context.temp_allocator
	stderr_b: [dynamic]byte
	stderr_b.allocator = context.temp_allocator
	buf: [1024]u8
	timeout := time.Millisecond * time.Duration(constants.DOCS_TIMEOUT_MS)
	max_out := constants.DOCS_MAX_CAPTURE_BYTES
	start := time.now()
	stdout_done := false
	stderr_done := false
	timed_out := false
	state: os.Process_State
	cancelled := false
	truncated := false

	for !stdout_done || !stderr_done {
		if http.cancel_requested() {
			cancelled = true
			shell_kill_process_tree(process)
			break
		}
		if time.since(start) >= timeout {
			timed_out = true
			shell_kill_process_tree(process)
			break
		}
		stderr_trunc := false
		if !stdout_done {
			stdout_done = docs_pipe_drain(stdout_r, &stdout_b, buf[:], max_out, &truncated)
		}
		if !stderr_done {
			stderr_done = docs_pipe_drain(stderr_r, &stderr_b, buf[:], max_out, &stderr_trunc)
		}
		wait_state, wait_err := os.process_wait(process, 0)
		if wait_err == nil && wait_state.exited {
			state = wait_state
			// Child exited, drain only what is already buffered. A detached
			// grandchild holding a write end must not turn this into a
			// blocking read past the timeout.
			_ = docs_pipe_drain(stdout_r, &stdout_b, buf[:], max_out, &truncated)
			_ = docs_pipe_drain(stderr_r, &stderr_b, buf[:], max_out, &stderr_trunc)
			break
		}
		time.sleep(5 * time.Millisecond)
	}
	if !state.exited {
		// Timeout and cancel already fired the kill, a pipes-EOF exit with
		// the child still running leaves a blocking wait unbounded. Kill
		// the tree first so the wait is bounded either way.
		shell_kill_process_tree(process)
		state, _ = os.process_wait(process)
	}
	if cancelled {
		return "", strings.clone("cancelled", allocator)
	}
	if timed_out {
		return "", fmt.aprintf("docs command timed out after %dms", constants.DOCS_TIMEOUT_MS, allocator = allocator)
	}
	if !state.exited {
		// Fail closed: no real status was captured.
		return "", strings.clone("process status unavailable", allocator)
	}
	if state.exit_code != 0 && len(stdout_b) == 0 {
		serr := strings.trim_space(string(stderr_b[:]))
		if len(serr) > 0 {
			if len(serr) > 240 {
				serr = serr[:240]
			}
			return "", fmt.aprintf("command failed (exit %d): %s", state.exit_code, serr, allocator = allocator)
		}
		return "", fmt.aprintf("command failed (exit %d)", state.exit_code, allocator = allocator)
	}
	out := strings.clone(string(stdout_b[:]), allocator)
	if truncated {
		note := fmt.tprintf("\n\n[truncated at %d capture bytes]", max_out)
		combined := strings.concatenate({out, note}, allocator)
		delete(out)
		return combined, ""
	}
	return out, ""
}

strip_man_overstrike :: proc(s: string, allocator := context.allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	i := 0
	for i < len(s) {
		if i + 1 < len(s) && s[i + 1] == '\b' {
			if i + 2 < len(s) {
				strings.write_byte(&b, s[i + 2])
				i += 3
				continue
			}
		}
		c := s[i]
		if c == '\r' {
			i += 1
			continue
		}
		strings.write_byte(&b, c)
		i += 1
	}
	return strings.to_string(b)
}
