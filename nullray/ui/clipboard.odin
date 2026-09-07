/*
Clipboard copy and paste via OSC 52 and common CLI tools.
*/

package ui

import "core:encoding/base64"
import "core:io"
import "core:os"
import "core:strings"

clipboard_copy :: proc(text: string) -> bool {
	if clipboard_copy_osc52(text) {
		return true
	}
	if clipboard_run_stdin([]string{"wl-copy"}, text) {
		return true
	}
	if clipboard_run_stdin([]string{"xclip", "-selection", "clipboard"}, text) {
		return true
	}
	if clipboard_run_stdin([]string{"xsel", "--clipboard", "--input"}, text) {
		return true
	}
	return false
}

clipboard_paste :: proc(allocator := context.allocator) -> (string, bool) {
	if out, ok := clipboard_run_stdout([]string{"wl-paste"}, allocator); ok {
		return out, true
	}
	if out, ok := clipboard_run_stdout([]string{"xclip", "-o", "-selection", "clipboard"}, allocator); ok {
		return out, true
	}
	if out, ok := clipboard_run_stdout([]string{"xsel", "--clipboard", "--output"}, allocator); ok {
		return out, true
	}
	return "", false
}

clipboard_base64_encode :: proc(data: []byte, allocator := context.allocator) -> (string, bool) {
	encoded, err := base64.encode(data, allocator = allocator)
	if err != nil {
		return "", false
	}
	for len(encoded) > 0 && encoded[len(encoded) - 1] == base64.PADDING {
		encoded = encoded[:len(encoded) - 1]
	}
	return encoded, true
}

@(private)
clipboard_copy_osc52 :: proc(text: string) -> bool {
	encoded, ok := clipboard_base64_encode(transmute([]u8)text, context.temp_allocator)
	if !ok {
		return false
	}
	seq := strings.concatenate(
		{
			"\x1b]52;c;",
			encoded,
			"\x07",
		},
		context.temp_allocator,
	)
	if len(seq) == 0 {
		return false
	}
	n, err := os.write(os.stdout, transmute([]u8)seq)
	return err == nil && n == len(seq)
}

@(private)
clipboard_run_stdin :: proc(command: []string, text: string) -> bool {
	if len(command) == 0 {
		return false
	}
	stdin_r, stdin_w, pipe_err := os.pipe()
	if pipe_err != nil {
		return false
	}
	defer os.close(stdin_r)
	stdout_r, stdout_w, pipe_err2 := os.pipe()
	if pipe_err2 != nil {
		return false
	}
	defer os.close(stdout_r)
	stderr_r, stderr_w, pipe_err3 := os.pipe()
	if pipe_err3 != nil {
		return false
	}
	defer os.close(stderr_r)

	process: os.Process
	{
		defer os.close(stdin_w)
		defer os.close(stdout_w)
		defer os.close(stderr_w)
		desc := os.Process_Desc{
			command = command,
			stdin = stdin_r,
			stdout = stdout_w,
			stderr = stderr_w,
		}
		start_err: os.Error
		process, start_err = os.process_start(desc)
		if start_err != nil {
			return false
		}
	}

	_, werr := os.write_string(stdin_w, text)
	_ = os.close(stdin_w)
	if werr != nil {
		_ = os.process_kill(process)
		_, _ = os.process_wait(process)
		return false
	}

	state, wait_err := os.process_wait(process, -1)
	if wait_err != nil {
		return false
	}
	return state.exit_code == 0
}

@(private)
clipboard_run_stdout :: proc(command: []string, allocator := context.allocator) -> (string, bool) {
	if len(command) == 0 {
		return "", false
	}
	stdout_r, stdout_w, pipe_err := os.pipe()
	if pipe_err != nil {
		return "", false
	}
	defer os.close(stdout_r)
	stderr_r, stderr_w, pipe_err2 := os.pipe()
	if pipe_err2 != nil {
		return "", false
	}
	defer os.close(stderr_r)

	process: os.Process
	{
		defer os.close(stdout_w)
		defer os.close(stderr_w)
		desc := os.Process_Desc{command = command, stdout = stdout_w, stderr = stderr_w}
		start_err: os.Error
		process, start_err = os.process_start(desc)
		if start_err != nil {
			return "", false
		}
	}

	out: [dynamic]u8
	out.allocator = allocator
	buf: [4096]u8
	for {
		n, rerr := os.read(stdout_r, buf[:])
		if n > 0 {
			append(&out, ..buf[:n])
		}
		if n == 0 || rerr == io.Error.EOF || rerr == os.General_Error.Broken_Pipe {
			break
		}
		if rerr != nil {
			_ = os.process_kill(process)
			_, _ = os.process_wait(process)
			return "", false
		}
	}

	state, wait_err := os.process_wait(process, -1)
	if wait_err != nil || state.exit_code != 0 {
		return "", false
	}
	return string(out[:]), true
}
