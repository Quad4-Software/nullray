// SPDX-License-Identifier: 0BSD
/*
Post-edit verify stop gate with truncated output and circuit breaker.
*/

package agent

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "nullray:constants"
import "nullray:provider"
import "nullray:tools"

verify_command_from_env :: proc(allocator := context.allocator) -> (cmd: string, disabled: bool) {
	if v, ok := os.lookup_env(constants.ENV_VERIFY, context.temp_allocator); ok {
		lower := strings.to_lower(v, context.temp_allocator)
		switch lower {
		case "0", "false", "off", "no", "disable":
			return "", true
		}
		if len(strings.trim_space(v)) > 0 {
			return strings.clone(v, allocator), false
		}
	}
	return "", false
}

verify_max_fails_from_env :: proc() -> int {
	if v, ok := os.lookup_env(constants.ENV_VERIFY_MAX_FAILS, context.temp_allocator); ok {
		n, ok2 := strconv.parse_int(v)
		if ok2 && n >= 1 {
			return n
		}
	}
	return constants.MAX_VERIFY_FAILS
}

rubric_enabled_from_env :: proc() -> bool {
	if v, ok := os.lookup_env(constants.ENV_RUBRIC, context.temp_allocator); ok {
		switch strings.to_lower(v, context.temp_allocator) {
		case "1", "true", "yes", "on":
			return true
		}
	}
	return false
}

resolve_verify_command :: proc(
	plan_verify: string,
	allocator := context.allocator,
) -> (cmd: string, disabled: bool) {
	env_cmd, off := verify_command_from_env(allocator)
	if off {
		return "", true
	}
	if len(env_cmd) > 0 {
		return env_cmd, false
	}
	if len(plan_verify) > 0 {
		first := first_verify_command(plan_verify, allocator)
		if len(first) > 0 {
			return first, false
		}
	}
	agents, _ := load_agents_md(context.temp_allocator)
	if len(agents) > 0 {
		cmds := parse_agents_verify_commands(agents, context.temp_allocator)
		if len(cmds) > 0 {
			return strings.clone(cmds[0], allocator), false
		}
	}
	return strings.clone("make test", allocator), false
}

truncate_bytes :: proc(s: string, max: int, allocator := context.allocator) -> string {
	if max <= 0 || len(s) <= max {
		return strings.clone(s, allocator)
	}
	head := s[:max]
	note := fmt.tprintf("\n[truncated at %d bytes]", max)
	return strings.concatenate({head, note}, allocator)
}

shell_output_ok :: proc(output: string) -> bool {
	lower := strings.to_lower(output, context.temp_allocator)
	if strings.contains(lower, "exit_code=") {
		idx := strings.index(lower, "exit_code=")
		rest := lower[idx + len("exit_code="):]
		end := 0
		for end < len(rest) && rest[end] >= '0' && rest[end] <= '9' {
			end += 1
		}
		if end > 0 {
			n, ok := strconv.parse_int(rest[:end])
			return ok && n == 0
		}
	}
	return true
}

/*
Run verify via run_shell. Returns ok and truncated output.
*/
run_verify_command :: proc(
	cmd: string,
	allocator := context.allocator,
) -> (ok: bool, output: string) {
	if len(strings.trim_space(cmd)) == 0 {
		return true, strings.clone("verify skipped (empty)", allocator)
	}
	args := fmt.aprintf(`{"command":%q}`, cmd, allocator = context.temp_allocator)
	result, err := tools.run(tools.registry(), "run_shell", args, "edit", allocator)
	if len(err) > 0 {
		out := truncate_bytes(err, constants.MAX_VERIFY_OUTPUT_BYTES, allocator)
		delete(result)
		delete(err)
		return false, out
	}
	ok = shell_output_ok(result)
	out := truncate_bytes(result, constants.MAX_VERIFY_OUTPUT_BYTES, allocator)
	delete(result)
	return ok, out
}

turn_had_writes :: proc(messages: []provider.Message) -> bool {
	for m in messages {
		if m.role != .Assistant {
			continue
		}
		for tc in m.tool_calls {
			switch tc.name {
			case "write_file", "edit_file", "apply_edits":
				return true
			}
		}
	}
	return false
}

/*
Build a budgeted diff-ish summary from write/edit tool calls in the turn.
*/
collect_turn_diff :: proc(messages: []provider.Message, allocator := context.allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	for m in messages {
		if m.role != .Assistant {
			continue
		}
		for tc in m.tool_calls {
			switch tc.name {
			case "write_file", "edit_file", "apply_edits":
				fmt.sbprintf(&b, "### %s\n%s\n\n", tc.name, tc.arguments)
			}
		}
	}
	text := strings.to_string(b)
	if len(text) == 0 {
		return strings.clone("(no file edits in this turn)", allocator)
	}
	if len(text) > constants.MAX_REVIEW_DIFF_CHARS {
		return strings.clone(text[:constants.MAX_REVIEW_DIFF_CHARS], allocator)
	}
	return strings.clone(text, allocator)
}

parse_block_findings :: proc(review_text: string) -> (blocks: int, total: int) {
	lines := strings.split_lines(review_text, context.temp_allocator)
	for line in lines {
		trimmed := strings.trim_space(line)
		lower := strings.to_lower(trimmed, context.temp_allocator)
		if strings.has_prefix(lower, "findings:") {
			continue
		}
		if strings.has_prefix(lower, "block|") {
			blocks += 1
			total += 1
		} else if strings.has_prefix(lower, "warn|") || strings.has_prefix(lower, "note|") {
			total += 1
		}
	}
	n, found := parse_findings_trailer(review_text)
	if found && n > total {
		total = n
	}
	return blocks, total
}
