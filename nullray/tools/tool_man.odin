// SPDX-License-Identifier: 0BSD
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
		cmd := fmt.aprintf(
			"apropos -l %s 2>/dev/null | head -n %d",
			kw,
			constants.MAX_APROPOS_LINES,
			allocator = context.temp_allocator,
		)
		out, oerr := run_capture_cmd(cmd, allocator)
		if oerr != "" {
			return "", oerr
		}
		if len(strings.trim_space(out)) == 0 {
			delete(out)
			return strings.clone("(no apropos matches)", allocator), ""
		}
		return out, ""
	}
}

@(private)
run_capture_cmd :: proc(command: string, allocator := context.allocator) -> (result: string, err: string) {
	return run_capture_argv([]string{"/bin/sh", "-c", command}, allocator)
}

run_capture_argv :: proc(argv: []string, allocator := context.allocator) -> (result: string, err: string) {
	return run_capture_argv_env(argv, nil, allocator)
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
		if !stdout_done {
			has_data, _ := os.pipe_has_data(stdout_r)
			if has_data {
				n, rerr := os.read(stdout_r, buf[:])
				if n > 0 {
					if len(stdout_b) < max_out {
						remain := max_out - len(stdout_b)
						take := n
						if take > remain {
							take = remain
							truncated = true
						}
						append(&stdout_b, ..buf[:take])
					} else {
						truncated = true
					}
				}
				if rerr == io.Error.EOF || rerr == os.General_Error.Broken_Pipe {
					stdout_done = true
				}
			}
		}
		if !stderr_done {
			has_data, _ := os.pipe_has_data(stderr_r)
			if has_data {
				n, rerr := os.read(stderr_r, buf[:])
				if n > 0 {
					if len(stderr_b) < max_out {
						remain := max_out - len(stderr_b)
						take := n
						if take > remain {
							take = remain
						}
						append(&stderr_b, ..buf[:take])
					}
				}
				if rerr == io.Error.EOF || rerr == os.General_Error.Broken_Pipe {
					stderr_done = true
				}
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
							truncated = true
						}
						append(&stdout_b, ..buf[:take])
					} else {
						truncated = true
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
						}
						append(&stderr_b, ..buf[:take])
					}
				}
				if n == 0 || rerr == io.Error.EOF || rerr == os.General_Error.Broken_Pipe {
					stderr_done = true
				}
			}
			break
		}
		time.sleep(5 * time.Millisecond)
	}
	state, _ := os.process_wait(process)
	if !state.exited {
		shell_kill_process_tree(process)
		state, _ = os.process_wait(process)
	}
	if cancelled {
		return "", strings.clone("cancelled", allocator)
	}
	if timed_out {
		return "", fmt.aprintf("docs command timed out after %dms", constants.DOCS_TIMEOUT_MS, allocator = allocator)
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
