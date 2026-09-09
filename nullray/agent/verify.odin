// SPDX-License-Identifier: 0BSD
/*
Post-edit verify stop gate with truncated output and circuit breaker.
Off by default. Opt in with NULLRAY_VERIFY=1|/verify on|CMD.
*/

package agent

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "nullray:constants"
import "nullray:elevate"
import "nullray:provider"
import "nullray:sandbox"
import "nullray:store"
import "nullray:tools"

VERIFY_USER_PREFIX :: "[nullray verify]"

verify_command_from_env :: proc(allocator := context.allocator) -> (cmd: string, disabled: bool) {
	v, ok := os.lookup_env(constants.ENV_VERIFY, context.temp_allocator)
	if !ok {
		return "", true
	}
	trimmed := strings.trim_space(v)
	if len(trimmed) == 0 {
		return "", true
	}
	lower := strings.to_lower(trimmed, context.temp_allocator)
	switch lower {
	case "0", "false", "off", "no", "disable":
		return "", true
	case "1", "true", "on", "yes", "enable":
		return "", false
	}
	return strings.clone(trimmed, allocator), false
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
	keys := []string{constants.ENV_RUBRIC, constants.ENV_SECURE_GATES}
	for key in keys {
		if v, ok := os.lookup_env(key, context.temp_allocator); ok {
			switch strings.to_lower(v, context.temp_allocator) {
			case "1", "true", "yes", "on":
				return true
			}
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
			if verify_command_missing_makefile(first) {
				delete(first)
				agents, _ := load_agents_md(context.temp_allocator)
				if len(agents) > 0 {
					cmds := parse_agents_verify_commands(agents, context.temp_allocator)
					if len(cmds) > 0 {
						return strings.clone(cmds[0], allocator), false
					}
				}
				return strings.clone("verify skipped: no Makefile", allocator), false
			}
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
	default_cmd := "make test"
	if verify_command_missing_makefile(default_cmd) {
		return strings.clone("verify skipped: no Makefile", allocator), false
	}
	return strings.clone(default_cmd, allocator), false
}

verify_command_missing_makefile :: proc(cmd: string) -> bool {
	t := strings.trim_space(cmd)
	if t != "make test" && !strings.has_prefix(t, "make test ") {
		return false
	}
	ws := ""
	if st := sandbox.state(); st != nil {
		ws = st.workspace
	}
	if len(ws) == 0 {
		if cwd, err := os.get_working_directory(context.temp_allocator); err == nil {
			ws = cwd
		}
	}
	if len(ws) == 0 {
		return false
	}
	path := fmt.tprintf("%s/Makefile", ws)
	return !os.exists(path)
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
Run verify via run_shell on the session tools registry.
Returns ok and full output (caller truncates for TUI / nudge).
*/
run_verify_command :: proc(
	cmd: string,
	reg: ^tools.Registry,
	allocator := context.allocator,
) -> (ok: bool, output: string) {
	if len(strings.trim_space(cmd)) == 0 {
		return true, strings.clone("verify skipped (empty)", allocator)
	}
	if strings.has_prefix(strings.trim_space(cmd), "verify skipped:") {
		return true, strings.clone(cmd, allocator)
	}
	if elevate.needs_elevate(cmd) {
		return false, strings.clone(
			"verify failed: elevated commands are not allowed in verify (use a non-sudo command or cached ticket outside verify)",
			allocator,
		)
	}
	if reg == nil {
		return false, strings.clone(
			"verify failed: no tools registry (internal). Use /verify off or set NULLRAY_VERIFY=0.",
			allocator,
		)
	}
	if _, found := tools.registry_find(reg, "run_shell"); !found {
		return false, strings.clone(
			"verify failed: run_shell is not registered. Use /verify off or set NULLRAY_VERIFY=0.",
			allocator,
		)
	}
	args := fmt.aprintf(`{{"command":%q}}`, cmd, allocator = context.temp_allocator)
	result, err := tools.run(reg, "run_shell", args, "edit", allocator)
	if len(err) > 0 {
		delete(result)
		return false, err
	}
	ok = shell_output_ok(result)
	return ok, result
}

format_verify_nudge :: proc(
	cmd: string,
	fail_n: int,
	max_fails: int,
	output: string,
	breaker: bool,
	allocator := context.allocator,
	artifact_id: string = "",
) -> string {
	findings := parse_diagnostics(output, allocator)
	defer delete_findings(&findings)
	findings_text := format_findings_block(findings[:], context.temp_allocator)

	excerpt := output
	if len(excerpt) > constants.ARTIFACT_EXCERPT_CHARS {
		excerpt = excerpt[:constants.ARTIFACT_EXCERPT_CHARS]
	}

	b: strings.Builder
	strings.builder_init(&b, allocator)
	if breaker {
		fmt.sbprintf(
			&b,
			"%s circuit breaker after %d fails\ncommand: %s\n",
			VERIFY_USER_PREFIX,
			fail_n,
			cmd,
		)
	} else {
		fmt.sbprintf(
			&b,
			"%s failed (%d/%d)\ncommand: %s\n",
			VERIFY_USER_PREFIX,
			fail_n,
			max_fails,
			cmd,
		)
	}
	if len(findings_text) > 0 {
		strings.write_string(&b, findings_text)
	}
	if len(artifact_id) > 0 {
		fmt.sbprintf(
			&b,
			"artifact=%s\nUse read_artifact or grep_artifact for the full verify log.\n",
			artifact_id,
		)
		strings.write_string(&b, "--- excerpt ---\n")
		strings.write_string(&b, excerpt)
		strings.write_string(&b, "\n")
	} else if lid_enabled() {
		strings.write_string(&b, "--- excerpt ---\n")
		strings.write_string(&b, excerpt)
		strings.write_string(&b, "\n")
	} else {
		raw := truncate_bytes(output, constants.MAX_VERIFY_OUTPUT_BYTES, context.temp_allocator)
		strings.write_string(&b, "---\n")
		strings.write_string(&b, raw)
		strings.write_string(&b, "\n---\n")
	}
	if breaker {
		strings.write_string(
			&b,
			"Stop. Tell the user verify is blocked until they fix the project or /verify off.",
		)
	} else {
		strings.write_string(
			&b,
			"Fix the failures, then stop when verify is green. Do not invent a tool named run_shell beyond the registered tools.",
		)
	}
	return strings.to_string(b)
}

verify_store_output :: proc(output: string, allocator := context.allocator) -> string {
	if !lid_enabled() {
		return ""
	}
	if len(output) == 0 {
		return ""
	}
	id, ok := store.artifact_store(output, allocator)
	if !ok {
		return ""
	}
	return id
}

turn_had_writes :: proc(messages: []provider.Message) -> bool {
	for m in messages {
		if m.role != .Assistant {
			continue
		}
		for tc in m.tool_calls {
			switch tc.name {
			case "write_file", "edit_file", "apply_edits", "scaffold":
				return true
			}
		}
	}
	return false
}

turn_had_tool_calls :: proc(messages: []provider.Message) -> bool {
	for m in messages {
		if m.role != .Assistant {
			continue
		}
		if len(m.tool_calls) > 0 {
			return true
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
