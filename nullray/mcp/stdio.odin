// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
MCP stdio subprocess session with line-framed JSON-RPC.
*/

package mcp

import "core:fmt"
import "core:io"
import "core:os"
import "core:strings"
import "core:time"
import "nullray:constants"

Stdio_Session :: struct {
	process:           os.Process,
	stdin_w:           ^os.File,
	stdout_r:          ^os.File,
	next_id:           int,
	server_id:         string,
	protocol_version:  string,
	// Bytes read past a newline but not yet returned. Servers often batch
	// multiple frames in one write.
	pending:           [dynamic]u8,
}

stdio_start :: proc(session: ^Stdio_Session, command: []string, cwd: string) -> (err: string) {
	if session == nil {
		return strings.clone("nil session")
	}
	if len(command) == 0 {
		return strings.clone("empty command")
	}

	stdin_r, stdin_w, pipe_err := os.pipe()
	if pipe_err != nil {
		return fmt.aprintf("stdin pipe failed: %v", pipe_err)
	}
	stdout_r, stdout_w, pipe_err2 := os.pipe()
	if pipe_err2 != nil {
		os.close(stdin_r)
		os.close(stdin_w)
		return fmt.aprintf("stdout pipe failed: %v", pipe_err2)
	}

	process: os.Process
	{
		defer os.close(stdin_r)
		defer os.close(stdout_w)
		desc := os.Process_Desc{
			working_dir = cwd,
			command = command,
			stdin = stdin_r,
			stdout = stdout_w,
		}
		start_err: os.Error
		process, start_err = os.process_start(desc)
		if start_err != nil {
			os.close(stdin_w)
			os.close(stdout_r)
			return fmt.aprintf("process start failed: %v", start_err)
		}
	}

	session^ = Stdio_Session{
		process = process,
		stdin_w = stdin_w,
		stdout_r = stdout_r,
		next_id = 1,
	}
	return ""
}

stdio_write_line :: proc(session: ^Stdio_Session, json: string) -> (err: string) {
	if session == nil || session.stdin_w == nil {
		return strings.clone("session not open")
	}
	line := strings.concatenate({json, "\n"}, context.temp_allocator)
	_, werr := os.write(session.stdin_w, transmute([]u8)line)
	if werr != nil {
		return fmt.aprintf("write failed: %v", werr)
	}
	return ""
}

stdio_read_line :: proc(
	session: ^Stdio_Session,
	timeout: time.Duration,
	allocator := context.allocator,
) -> (
	line: string,
	err: string,
) {
	if session == nil || session.stdout_r == nil {
		return "", strings.clone("session not open", allocator)
	}

	buf: [256]u8
	start := time.now()

	for {
		if nl, ok := stdio_take_line(session, allocator); ok {
			return nl, ""
		}
		if time.since(start) >= timeout {
			return "", strings.clone("read timeout", allocator)
		}

		has_data, read_err := os.pipe_has_data(session.stdout_r)
		if has_data {
			n, rerr := os.read(session.stdout_r, buf[:])
			if n > 0 {
				append(&session.pending, ..buf[:n])
			}
			if rerr == io.Error.EOF || rerr == os.General_Error.Broken_Pipe {
				if nl, ok := stdio_take_line(session, allocator); ok {
					return nl, ""
				}
				if len(session.pending) > 0 {
					out := strings.clone(string(session.pending[:]), allocator)
					clear(&session.pending)
					return out, ""
				}
				return "", strings.clone("eof", allocator)
			}
		} else if read_err == io.Error.EOF || read_err == os.General_Error.Broken_Pipe {
			if len(session.pending) > 0 {
				out := strings.clone(string(session.pending[:]), allocator)
				clear(&session.pending)
				return out, ""
			}
			return "", strings.clone("eof", allocator)
		}

		time.sleep(time.Millisecond * time.Duration(constants.POLL_TIMEOUT_MS))
	}
}

// Pop one line from the pending carry buffer. ok=false when incomplete.
@(private)
stdio_take_line :: proc(session: ^Stdio_Session, allocator := context.allocator) -> (string, bool) {
	for b, i in session.pending {
		if b == '\n' {
			line := strings.clone(string(session.pending[:i]), allocator)
			rest := len(session.pending) - i - 1
			copy(session.pending[:rest], session.pending[i + 1:])
			resize(&session.pending, rest)
			return line, true
		}
	}
	return "", false
}

stdio_request :: proc(
	session: ^Stdio_Session,
	method: string,
	params_json: string,
	allocator := context.allocator,
) -> (
	result_json: string,
	err: string,
) {
	if session == nil {
		return "", strings.clone("nil session", allocator)
	}

	id := session.next_id
	session.next_id += 1
	req := build_request(id, method, params_json, context.temp_allocator)
	defer delete(req)

	if werr := stdio_write_line(session, req); werr != "" {
		return "", strings.clone(werr, allocator)
	}

	timeout := time.Millisecond * time.Duration(constants.SHELL_TIMEOUT_MS)
	for {
		line, rerr := stdio_read_line(session, timeout, context.temp_allocator)
		if rerr != "" {
			return "", strings.clone(rerr, allocator)
		}
		if len(line) == 0 {
			continue
		}
		res, perr, matched := parse_response_line(line, id, allocator)
		if !matched {
			continue
		}
		if perr != "" {
			return "", perr
		}
		return res, ""
	}
}

stdio_close :: proc(session: ^Stdio_Session) {
	if session == nil {
		return
	}
	delete(session.protocol_version)
	delete(session.pending)
	session.protocol_version = ""
	if session.stdin_w != nil {
		os.close(session.stdin_w)
		session.stdin_w = nil
	}
	if session.stdout_r != nil {
		os.close(session.stdout_r)
		session.stdout_r = nil
	}
	if session.process.pid != 0 {
		_ = os.process_kill(session.process)
		_, _ = os.process_wait(session.process, time.Second * 5)
		session.process = {}
	}
}
