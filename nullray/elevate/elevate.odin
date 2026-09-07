// SPDX-License-Identifier: 0BSD
/*
Elevated command auth: classify, circuit breaker, askpass, broker.
Passwords never enter tool results or provider messages.
*/

package elevate

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "nullray:constants"

Backend :: enum {
	None,
	Sudo,
	Doas,
	Pkexec,
	Su,
	Runas,
}

Outcome :: enum {
	Ticket,
	Askpass,
	Denied,
	Failed,
	Cancelled,
	Locked,
	Busy,
	Needs_Tty,
	Polkit_Agent,
	Unsupported,
}

Mode :: enum {
	Ask,
	Deny,
	Ticket,
}

Kind :: enum {
	Ok,
	Denied_Shell,
	Denied_Password_Args,
	Locked,
	Busy,
	Needs_Tty,
	Auth_Failed,
	Auth_Cancelled,
	Polkit_Agent,
	Unsupported,
	Exec_Failed,
	Requiretty,
	Missing_Binary,
}

Result :: struct {
	exit_code:  int,
	stdout:     string,
	stderr:     string,
	outcome:    Outcome,
	kind:       Kind,
	backend:    Backend,
	used_password: bool,
	err:        string,
}

g_self_exe: string
g_headless: bool
g_started:  bool

elevate_mode_from_env :: proc() -> Mode {
	if v, ok := os.lookup_env(constants.ENV_ELEVATE, context.temp_allocator); ok {
		switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
		case "deny", "off", "0", "false", "no":
			return .Deny
		case "ticket", "cached", "nopass":
			return .Ticket
		}
	}
	return .Ask
}

max_fails_from_env :: proc() -> int {
	if v, ok := os.lookup_env(constants.ENV_ELEVATE_MAX_FAILS, context.temp_allocator); ok {
		n, ok2 := strconv.parse_int(strings.trim_space(v))
		if ok2 && n >= 1 {
			return n
		}
	}
	return constants.DEFAULT_ELEVATE_MAX_FAILS
}

lock_secs_from_env :: proc() -> i64 {
	if v, ok := os.lookup_env(constants.ENV_ELEVATE_LOCK_SECS, context.temp_allocator); ok {
		n, ok2 := strconv.parse_i64(strings.trim_space(v))
		if ok2 && n >= 1 {
			return n
		}
	}
	return i64(constants.DEFAULT_ELEVATE_LOCK_SECS)
}

modal_secs_from_env :: proc() -> i64 {
	if v, ok := os.lookup_env(constants.ENV_ELEVATE_MODAL_SECS, context.temp_allocator); ok {
		n, ok2 := strconv.parse_i64(strings.trim_space(v))
		if ok2 && n >= 5 {
			return n
		}
	}
	return i64(constants.DEFAULT_ELEVATE_MODAL_SECS)
}

set_self_exe :: proc(path: string) {
	if len(g_self_exe) > 0 {
		delete(g_self_exe)
	}
	g_self_exe = strings.clone(path)
}

self_exe :: proc() -> string {
	return g_self_exe
}

set_headless :: proc(on: bool) {
	g_headless = on
}

headless :: proc() -> bool {
	return g_headless
}

outcome_label :: proc(o: Outcome) -> string {
	switch o {
	case .Ticket:
		return "ticket"
	case .Askpass:
		return "askpass"
	case .Denied:
		return "denied"
	case .Failed:
		return "failed"
	case .Cancelled:
		return "cancelled"
	case .Locked:
		return "locked"
	case .Busy:
		return "busy"
	case .Needs_Tty:
		return "needs_tty"
	case .Polkit_Agent:
		return "polkit_agent"
	case .Unsupported:
		return "unsupported"
	}
	return "unknown"
}

format_tool_result :: proc(r: Result, allocator := context.allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	strings.write_string(&b, fmt.aprintf("exit_code=%d\n", r.exit_code, allocator = context.temp_allocator))
	if len(r.stdout) > 0 {
		strings.write_string(&b, r.stdout)
	}
	if len(r.stderr) > 0 {
		if len(r.stdout) > 0 {
			strings.write_string(&b, "\n")
		}
		strings.write_string(&b, r.stderr)
	}
	if len(r.err) > 0 && len(r.stdout) == 0 && len(r.stderr) == 0 {
		strings.write_string(&b, r.err)
		strings.write_string(&b, "\n")
	}
	strings.write_string(&b, fmt.aprintf("\nelevation=%s\n", outcome_label(r.outcome), allocator = context.temp_allocator))
	return strings.to_string(b)
}

result_destroy :: proc(r: ^Result) {
	if r == nil {
		return
	}
	delete(r.stdout)
	delete(r.stderr)
	delete(r.err)
	r^ = {}
}

is_nonretryable_elevate_text :: proc(text: string) -> bool {
	if strings.contains(text, "elevation=locked") ||
		strings.contains(text, "elevation=cancelled") ||
		strings.contains(text, "elevation=failed") ||
		strings.contains(text, "elevation=denied") ||
		strings.contains(text, "elevation=busy") ||
		strings.contains(text, "elevation=needs_tty") ||
		strings.contains(text, "elevation=polkit_agent") {
		return true
	}
	if strings.contains(text, "auth_failed") ||
		strings.contains(text, "elevation_locked") ||
		strings.contains(text, "auth_cancelled") ||
		strings.contains(text, "elevation_busy") ||
		strings.contains(text, "elevation_needs_tty") ||
		strings.contains(text, "elevation_polkit_agent") {
		return true
	}
	return false
}

askpass_path :: proc(allocator := context.allocator) -> string {
	if v, ok := os.lookup_env(constants.ENV_ASKPASS, context.temp_allocator); ok {
		trimmed := strings.trim_space(v)
		if len(trimmed) > 0 {
			return strings.clone(trimmed, allocator)
		}
	}
	if len(g_self_exe) > 0 {
		return fmt.aprintf("%s --askpass", g_self_exe, allocator = allocator)
	}
	return strings.clone("nullray --askpass", allocator)
}
