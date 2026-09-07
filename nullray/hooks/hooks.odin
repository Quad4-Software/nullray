// SPDX-License-Identifier: 0BSD
/*
User hook loading and bounded subprocess execution.
*/

package hooks

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:strings"
import "core:time"
import "nullray:constants"
import "nullray:sandbox"

Event :: enum {
	PreToolUse,
	PostToolUse,
	SessionStart,
	SessionEnd,
	Stop,
	PreCommit,
}

Hook_File :: struct {
	pre_tool_use:  []string `json:"PreToolUse"`,
	post_tool_use: []string `json:"PostToolUse"`,
	session_start: []string `json:"SessionStart"`,
	session_end:   []string `json:"SessionEnd"`,
	stop:          []string `json:"Stop"`,
	pre_commit:    []string `json:"PreCommit"`,
}

Result :: struct {
	blocked: bool,
	message: string,
}

run :: proc(event: Event, tool_name := "", payload := "", allocator := context.allocator) -> Result {
	if disabled() {
		return {}
	}
	cfg := sandbox.resolve_config_dir(context.temp_allocator)
	global_path, _ := filepath.join({cfg, constants.HOOKS_FILE}, context.temp_allocator)
	st := sandbox.state()
	workspace := ""
	if st != nil {
		workspace = st.workspace
	}
	if len(workspace) == 0 {
		workspace, _ = os.get_working_directory(context.temp_allocator)
	}
	local_path, _ := filepath.join({workspace, ".nullray", constants.HOOKS_FILE}, context.temp_allocator)
	paths := []string{global_path, local_path}
	for path in paths {
		res := run_file(path, event, tool_name, payload, allocator)
		if res.blocked {
			return res
		}
		delete(res.message)
	}
	return {}
}

event_name :: proc(event: Event) -> string {
	switch event {
	case .PreToolUse:
		return "PreToolUse"
	case .PostToolUse:
		return "PostToolUse"
	case .SessionStart:
		return "SessionStart"
	case .SessionEnd:
		return "SessionEnd"
	case .Stop:
		return "Stop"
	case .PreCommit:
		return "PreCommit"
	}
	return "Unknown"
}

@(private)
disabled :: proc() -> bool {
	if v, ok := os.lookup_env(constants.ENV_HOOKS, context.temp_allocator); ok {
		lower := strings.to_lower(strings.trim_space(v), context.temp_allocator)
		return lower == "0" || lower == "false" || lower == "off" || lower == "no"
	}
	return false
}

@(private)
commands_for :: proc(cfg: ^Hook_File, event: Event) -> []string {
	switch event {
	case .PreToolUse:
		return cfg.pre_tool_use
	case .PostToolUse:
		return cfg.post_tool_use
	case .SessionStart:
		return cfg.session_start
	case .SessionEnd:
		return cfg.session_end
	case .Stop:
		return cfg.stop
	case .PreCommit:
		return cfg.pre_commit
	}
	return nil
}

@(private)
run_file :: proc(path: string, event: Event, tool_name, payload: string, allocator := context.allocator) -> Result {
	data, rerr := os.read_entire_file(path, context.temp_allocator)
	if rerr != nil {
		return {}
	}
	cfg: Hook_File
	if jerr := json.unmarshal(data, &cfg, .JSON, context.temp_allocator); jerr != nil {
		return Result{message = fmt.aprintf("hook config parse failed for %s: %v", path, jerr, allocator = allocator)}
	}
	input := fmt.aprintf(
		`{"event":%q,"tool":%q,"payload":%q}`,
		event_name(event),
		tool_name,
		payload,
		allocator = context.temp_allocator,
	)
	for command in commands_for(&cfg, event) {
		exit_code, timed_out, err := run_command(command, input)
		if err != "" {
			continue
		}
		if timed_out {
			continue
		}
		if exit_code == 2 {
			return Result{
				blocked = true,
				message = fmt.aprintf("%s hook blocked %s", event_name(event), tool_name, allocator = allocator),
			}
		}
	}
	return {}
}

@(private)
timeout_ms :: proc() -> int {
	if v, ok := os.lookup_env(constants.ENV_HOOK_TIMEOUT_MS, context.temp_allocator); ok {
		if n, nok := strconv.parse_int(v); nok && n > 0 {
			return n
		}
	}
	return 5_000
}

@(private)
run_command :: proc(command, input: string) -> (exit_code: int, timed_out: bool, err: string) {
	stdin_r, stdin_w, perr := os.pipe()
	if perr != nil {
		return 0, false, fmt.tprintf("hook pipe failed: %v", perr)
	}
	defer os.close(stdin_r)
	process: os.Process
	{
		defer os.close(stdin_w)
		argv: [3]string
		when ODIN_OS == .Windows {
			argv = {"cmd.exe", "/C", command}
		} else {
			argv = {"/bin/sh", "-c", command}
		}
		desc := os.Process_Desc{
			command = argv[:],
			stdin = stdin_r,
		}
		start_err: os.Error
		process, start_err = os.process_start(desc)
		if start_err != nil {
			return 0, false, fmt.tprintf("hook exec failed: %v", start_err)
		}
		_, _ = os.write(stdin_w, transmute([]u8)input)
	}
	start := time.now()
	for {
		state, wait_err := os.process_wait(process, 0)
		if wait_err == nil && state.exited {
			return state.exit_code, false, ""
		}
		if time.since(start) >= time.Millisecond * time.Duration(timeout_ms()) {
			_ = os.process_kill(process)
			state, _ = os.process_wait(process)
			return state.exit_code, true, ""
		}
	}
}
