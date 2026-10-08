// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Clipboard copy and paste via wl-copy/xclip first, then OSC 52.

Prefer native tools on Wayland: OSC 52 often never reaches the compositor
clipboard even when the write to stdout "succeeds".
*/

package ui

import "core:encoding/base64"
import "core:io"
import "core:os"
import "core:strings"
import "core:time"

clipboard_copy :: proc(text: string) -> bool {
	if len(text) == 0 {
		return false
	}
	// Native tools first (real OS clipboard).
	if clipboard_wayland() {
		if clipboard_run_stdin([]string{"wl-copy", "--type", "text/plain"}, text) {
			return true
		}
		if clipboard_run_stdin([]string{"wl-copy"}, text) {
			return true
		}
		// Some setups only speak stdin without type flags.
		if clipboard_run_stdin([]string{"wl-copy", "-n"}, text) {
			return true
		}
	}
	if clipboard_run_stdin([]string{"xclip", "-selection", "clipboard"}, text) {
		return true
	}
	if clipboard_run_stdin([]string{"xclip", "-selection", "primary"}, text) {
		// Also primary for middle-click paste users
		_ = clipboard_run_stdin([]string{"xclip", "-selection", "clipboard"}, text)
		return true
	}
	if clipboard_run_stdin([]string{"xsel", "--clipboard", "--input"}, text) {
		return true
	}
	// Last resort: terminal clipboard (works in some SSH/kitty setups).
	if clipboard_copy_osc52(text) {
		return true
	}
	return false
}

clipboard_paste :: proc(allocator := context.allocator) -> (string, bool) {
	if clipboard_wayland() {
		if out, ok := clipboard_run_stdout([]string{"wl-paste", "--no-newline", "--type", "text/plain"}, allocator); ok {
			return out, true
		}
		if out, ok := clipboard_run_stdout([]string{"wl-paste", "--no-newline"}, allocator); ok {
			return out, true
		}
		if out, ok := clipboard_run_stdout([]string{"wl-paste"}, allocator); ok {
			return out, true
		}
	}
	if out, ok := clipboard_run_stdout([]string{"xclip", "-o", "-selection", "clipboard"}, allocator); ok {
		return out, true
	}
	if out, ok := clipboard_run_stdout([]string{"xsel", "--clipboard", "--output"}, allocator); ok {
		return out, true
	}
	return "", false
}

clipboard_wayland :: proc() -> bool {
	if v, ok := os.lookup_env("WAYLAND_DISPLAY", context.temp_allocator); ok && len(strings.trim_space(v)) > 0 {
		return true
	}
	if v, ok := os.lookup_env("XDG_SESSION_TYPE", context.temp_allocator); ok {
		if strings.to_lower(strings.trim_space(v), context.temp_allocator) == "wayland" {
			return true
		}
	}
	// Socket present under XDG_RUNTIME_DIR even if WAYLAND_DISPLAY unset in nested tools.
	if rt, ok := os.lookup_env("XDG_RUNTIME_DIR", context.temp_allocator); ok {
		// common: wayland-0
		cand := strings.concatenate({rt, "/wayland-0"}, context.temp_allocator)
		if os.exists(cand) {
			return true
		}
	}
	return false
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
	// Ensure tool exists: cheap PATH check via failed start is fine.
	stdin_r, stdin_w, pipe_err := os.pipe()
	if pipe_err != nil {
		return false
	}
	stdout_r, stdout_w, pipe_err2 := os.pipe()
	if pipe_err2 != nil {
		os.close(stdin_r)
		os.close(stdin_w)
		return false
	}
	stderr_r, stderr_w, pipe_err3 := os.pipe()
	if pipe_err3 != nil {
		os.close(stdin_r)
		os.close(stdin_w)
		os.close(stdout_r)
		os.close(stdout_w)
		return false
	}

	// Child inherits read ends. Parent keeps stdin_w open until after write.
	// Pass through WAYLAND_DISPLAY / XDG_RUNTIME_DIR from current env (nil env inherits).
	desc := os.Process_Desc{
		command = command,
		stdin = stdin_r,
		stdout = stdout_w,
		stderr = stderr_w,
	}
	process, start_err := os.process_start(desc)
	os.close(stdin_r)
	os.close(stdout_w)
	os.close(stderr_w)
	// Drain ignored stdout/err so the child cannot block on full pipes.
	os.close(stdout_r)
	os.close(stderr_r)
	if start_err != nil {
		os.close(stdin_w)
		return false
	}

	// Write in chunks so large selections still work.
	data := transmute([]u8)text
	off := 0
	for off < len(data) {
		n, werr := os.write(stdin_w, data[off:])
		if werr != nil {
			os.close(stdin_w)
			_ = os.process_kill(process)
			_, _ = os.process_wait(process)
			return false
		}
		if n <= 0 {
			break
		}
		off += n
	}
	os.close(stdin_w)

	// Bounded wait: wl-copy can hang if compositor is wedged.
	deadline := time.now()
	timeout := time.Second * 3
	for {
		state, wait_err := os.process_wait(process, time.Millisecond * 50)
		if wait_err == nil && state.exited {
			return state.exit_code == 0
		}
		if time.since(deadline) >= timeout {
			_ = os.process_kill(process)
			_, _ = os.process_wait(process)
			return false
		}
	}
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
	deadline := time.now()
	timeout := time.Second * 3
	for {
		if time.since(deadline) >= timeout {
			_ = os.process_kill(process)
			_, _ = os.process_wait(process)
			return "", false
		}
		has, _ := os.pipe_has_data(stdout_r)
		if has {
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
			continue
		}
		state, wait_err := os.process_wait(process, time.Millisecond * 20)
		if wait_err == nil && state.exited {
			// final drain
			for {
				has2, _ := os.pipe_has_data(stdout_r)
				if !has2 {
					break
				}
				n, _ := os.read(stdout_r, buf[:])
				if n > 0 {
					append(&out, ..buf[:n])
				} else {
					break
				}
			}
			if state.exit_code != 0 {
				return "", false
			}
			return string(out[:]), true
		}
	}
	state, wait_err := os.process_wait(process, -1)
	if wait_err != nil || state.exit_code != 0 {
		return "", false
	}
	return string(out[:]), true
}
