// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
External harness tools. harness_list shows configured agent CLIs and whether
their binary resolved on PATH, harness_run delegates a prompt to one of them.

harness_run spawns a subprocess, so it is kind .Shell: it shares the run_shell
gate class and is blocked in ask/plan/review modes. Output is capped to
HARNESS_MAX_OUTPUT head+tail by the harness package, it never goes through a
shell and only defined harness ids can name a binary.
*/

package tools

import "core:fmt"
import "core:strings"
import "nullray:harness"
import "nullray:http"
import "nullray:sandbox"
import "nullray:subagent"

register_harness_tools :: proc(r: ^Registry) {
	registry_register(r, Tool{
		name = "harness_list",
		description = "List known external agent CLIs: id, resolved binary or not found, config source",
		schema_json = `{"type":"object","properties":{}}`,
		kind = .Read,
		run = tool_harness_list,
	})
	registry_register(r, Tool{
		name = "harness_run",
		description = "Run a task on an external agent CLI (see harness_list for engine ids); returns its text output",
		schema_json = `{"type":"object","properties":{"engine":{"type":"string","description":"harness id from harness_list"},"prompt":{"type":"string","description":"task text passed as a single argv element"},"timeout_sec":{"type":"integer","description":"optional seconds, clamped to 1800"}},"required":["engine","prompt"]}`,
		kind = .Shell,
		run = tool_harness_run,
	})
}

tool_harness_list :: proc(args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	_ = args_json
	if !harness.harness_enabled() {
		return "", strings.clone(harness.HARNESS_DISABLED, allocator)
	}
	return harness.list_available(allocator), ""
}

@(private)
harness_cancel_check :: proc() -> bool {
	return http.cancel_requested()
}

tool_harness_run :: proc(args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	if !harness.harness_enabled() {
		return "", strings.clone(harness.HARNESS_DISABLED, allocator)
	}
	engine, eerr := json_arg_string(args_json, "engine", allocator)
	if eerr != "" {
		return "", eerr
	}
	defer delete(engine)
	prompt, perr := json_arg_string(args_json, "prompt", allocator)
	if perr != "" {
		return "", perr
	}
	defer delete(prompt)
	timeout_sec, terr := json_arg_int_optional(args_json, "timeout_sec", 0, allocator)
	if terr != "" {
		return "", terr
	}

	// Same permission class as run_shell: the engine id is the probe string
	// so NULLRAY_SHELL_ALLOW/DENY entries and the ask-mode /allow handoff
	// select which external CLIs may run. The prompt is intentionally not
	// scanned here, it is data for the child agent, not a shell command.
	allowed, reason := shell_command_allowed(strings.trim_space(engine), allocator)
	if !allowed {
		return "", reason
	}
	defer delete(reason)

	if shell_err := subagent.check_shell_allowed(engine, allocator); len(shell_err) > 0 {
		return "", shell_err
	}
	if !sandbox.shell_allowed(sandbox.state()) {
		return "", strings.clone("shell not allowed by sandbox", allocator)
	}
	workspace, werr := resolve_cwd_jail(workspace_root(context.temp_allocator), allocator)
	if werr != "" {
		return "", werr
	}
	defer delete(workspace, allocator)
	if !sandbox.path_allowed(sandbox.state(), workspace, true) {
		return "", strings.clone("workspace path not allowed for shell", allocator)
	}

	out, rerr := harness.run(engine, prompt, workspace, timeout_sec, allocator, harness_cancel_check)
	if rerr != "" {
		return "", rerr
	}
	if hint := sandbox.exec_denied_hint(out, allocator); len(hint) > 0 {
		merged := fmt.aprintf("%s\n%s", out, hint, allocator = allocator)
		delete(out)
		delete(hint)
		out = merged
	}
	if len(strings.trim_space(out)) == 0 {
		delete(out)
		return fmt.aprintf("harness %s produced no output", strings.trim_space(engine), allocator = allocator), ""
	}
	return out, ""
}
