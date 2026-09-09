// SPDX-License-Identifier: 0BSD
package run

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "nullray:agent"
import "nullray:constants"
import "nullray:session"

@(private)
last_assistant_text :: proc(s: ^session.Session, allocator := context.allocator) -> string {
	for i := len(s.messages) - 1; i >= 0; i -= 1 {
		if s.messages[i].role == .Assistant && len(s.messages[i].content) > 0 {
			return strings.clone(s.messages[i].content, allocator)
		}
	}
	return ""
}

@(private)
session_had_tool_activity :: proc(s: ^session.Session) -> bool {
	for m in s.messages {
		if m.role == .Tool {
			return true
		}
		if m.role == .Assistant && len(m.tool_calls) > 0 {
			return true
		}
	}
	return false
}

@(private)
write_text_file :: proc(path, text: string, allocator := context.allocator) -> string {
	if merr := agent.ensure_parent_dirs(path); len(merr) > 0 {
		return strings.clone(merr, allocator)
	}
	if werr := os.write_entire_file(path, transmute([]u8)text); werr != nil {
		return fmt.aprintf("write %s failed: %v", path, werr, allocator = allocator)
	}
	return ""
}

@(private)
ephemeral_forced :: proc() -> bool {
	if v, ok := os.lookup_env(constants.ENV_EPHEMERAL, context.temp_allocator); ok {
		switch strings.to_lower(v, context.temp_allocator) {
		case "1", "true", "yes", "on":
			return true
		}
	}
	return false
}

print_timeout_from_env :: proc() -> int {
	if v, ok := os.lookup_env(constants.ENV_PRINT_TIMEOUT, context.temp_allocator); ok && len(v) > 0 {
		n, okp := parse_positive_int(v)
		if okp {
			return n
		}
	}
	return constants.DEFAULT_PRINT_TIMEOUT_SEC
}

@(private)
parse_positive_int :: proc(s: string) -> (int, bool) {
	n := 0
	if len(s) == 0 {
		return 0, false
	}
	for c in s {
		if c < '0' || c > '9' {
			return 0, false
		}
		n = n * 10 + int(c - '0')
	}
	return n, n > 0
}

stdin_context_max_chars :: proc() -> int {
	if v, ok := os.lookup_env(constants.ENV_STDIN_CONTEXT_MAX, context.temp_allocator); ok {
		n, n_ok := strconv.parse_int(v)
		if n_ok && n > 0 {
			return n
		}
	}
	return constants.STDIN_CONTEXT_MAX_CHARS
}

build_prompt :: proc(positional: string, message_file: string, read_stdin: bool, allocator := context.allocator) -> (string, string) {
	b: strings.Builder
	strings.builder_init(&b, allocator)

	has_args := len(strings.trim_space(positional)) > 0
	stdin_data := ""
	stdin_ok := false
	if read_stdin {
		stdin_data, stdin_ok = read_all_stdin(context.temp_allocator)
	}

	if has_args && stdin_ok && len(stdin_data) > 0 {
		cap_n := stdin_context_max_chars()
		body := stdin_data
		if len(body) > cap_n {
			body = body[:cap_n]
		}
		strings.write_string(&b, "[stdin context]\n")
		strings.write_string(&b, body)
		strings.write_string(&b, "\n\n")
	}

	if len(positional) > 0 {
		strings.write_string(&b, positional)
	}
	if len(message_file) > 0 {
		data, err := os.read_entire_file(message_file, context.temp_allocator)
		if err != nil {
			return "", fmt.aprintf("read --message-file: %v", err, allocator = allocator)
		}
		if strings.builder_len(b) > 0 {
			strings.write_string(&b, "\n\n")
		}
		strings.write_string(&b, string(data))
	}
	if !has_args && len(message_file) == 0 && stdin_ok && len(stdin_data) > 0 {
		strings.write_string(&b, stdin_data)
	}
	return strings.to_string(b), ""
}
