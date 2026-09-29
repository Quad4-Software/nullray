// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
User hook loading and bounded subprocess execution.
*/

package hooks

import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:thread"
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

@(private)
g_hooks_mu: sync.Mutex
@(private)
g_local_hooks_mtime: i64 = -1
@(private)
g_local_hooks_path: string
@(private)
g_local_hooks_trusted: bool

/*
Re-approve workspace .nullray/hooks.json after mid-session rewrite.
*/
hooks_trust_workspace :: proc() -> bool {
	st := sandbox.state()
	workspace := ""
	if st != nil {
		workspace = st.workspace
	}
	if len(workspace) == 0 {
		workspace, _ = os.get_working_directory(context.temp_allocator)
	}
	local_path, _ := filepath.join({workspace, ".nullray", constants.HOOKS_FILE}, context.temp_allocator)
	info, err := os.stat(local_path, context.temp_allocator)
	sync.mutex_lock(&g_hooks_mu)
	defer sync.mutex_unlock(&g_hooks_mu)
	if err != nil {
		g_local_hooks_mtime = -1
		g_local_hooks_trusted = true
		return true
	}
	mt := time.to_unix_seconds(info.modification_time)
	if len(g_local_hooks_path) > 0 {
		delete(g_local_hooks_path, runtime.heap_allocator())
	}
	g_local_hooks_path = strings.clone(local_path, runtime.heap_allocator())
	g_local_hooks_mtime = mt
	g_local_hooks_trusted = true
	return true
}

hooks_workspace_source :: proc(allocator := context.allocator) -> string {
	st := sandbox.state()
	workspace := ""
	if st != nil {
		workspace = st.workspace
	}
	if len(workspace) == 0 {
		workspace, _ = os.get_working_directory(context.temp_allocator)
	}
	local_path, _ := filepath.join({workspace, ".nullray", constants.HOOKS_FILE}, allocator)
	return local_path
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
	if blocked, msg := local_hooks_trust_check(local_path, allocator); blocked {
		return Result{blocked = true, message = msg}
	}
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
local_hooks_trust_check :: proc(path: string, allocator := context.allocator) -> (blocked: bool, message: string) {
	info, err := os.stat(path, context.temp_allocator)
	if err != nil {
		return false, ""
	}
	mt := time.to_unix_seconds(info.modification_time)
	// Hook trust state is shared across chat and subagent workers; guard it.
	sync.mutex_lock(&g_hooks_mu)
	defer sync.mutex_unlock(&g_hooks_mu)
	if g_local_hooks_mtime < 0 {
		g_local_hooks_mtime = mt
		if len(g_local_hooks_path) > 0 {
			delete(g_local_hooks_path, runtime.heap_allocator())
		}
		g_local_hooks_path = strings.clone(path, runtime.heap_allocator())
		g_local_hooks_trusted = true
		return false, ""
	}
	if mt == g_local_hooks_mtime && g_local_hooks_trusted {
		return false, ""
	}
	if v, ok := os.lookup_env(constants.ENV_HOOKS_TRUST, context.temp_allocator); ok {
		switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
		case "1", "true", "yes", "on":
			g_local_hooks_mtime = mt
			g_local_hooks_trusted = true
			os.unset_env(constants.ENV_HOOKS_TRUST)
			return false, ""
		}
	}
	return true, fmt.aprintf(
		"workspace hooks.json changed this session (trust handoff). re-approve with /hooks trust or NULLRAY_HOOKS_TRUST=1",
		allocator = allocator,
	)
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
		`{{"event":%q,"tool":%q,"payload":%q}}`,
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
Hook_Writer :: struct {
	w:     ^os.File,
	input: string,
}

// Feeds hook stdin from a thread so a child that never reads stdin cannot
// deadlock the caller past its timeout. Killing the child breaks the pipe.
@(private)
hook_writer_proc :: proc(data: rawptr) {
	w := cast(^Hook_Writer)data
	_, _ = os.write(w.w, transmute([]u8)w.input)
	// Close the write end so commands reading stdin to EOF finish.
	_ = os.close(w.w)
}

@(private)
run_command :: proc(command, input: string) -> (exit_code: int, timed_out: bool, err: string) {
	stdin_r, stdin_w, perr := os.pipe()
	if perr != nil {
		return 0, false, fmt.tprintf("hook pipe failed: %v", perr)
	}
	defer os.close(stdin_r)
	process: os.Process
	writer: Hook_Writer
	wth: ^thread.Thread
	{
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
			os.close(stdin_w)
			return 0, false, fmt.tprintf("hook exec failed: %v", start_err)
		}
		writer = Hook_Writer{w = stdin_w, input = input}
		wth = thread.create_and_start_with_data(&writer, hook_writer_proc)
		if wth == nil {
			os.close(stdin_w)
		}
	}
	// Join the writer before closing the parent write end, and only after the
	// child exits or is killed (a dead child makes any blocked write fail).
	exit_code = 0
	start := time.now()
	for {
		state, wait_err := os.process_wait(process, 0)
		if wait_err == nil && state.exited {
			exit_code = state.exit_code
			break
		}
		if time.since(start) >= time.Millisecond * time.Duration(timeout_ms()) {
			_ = os.process_kill(process)
			state, _ = os.process_wait(process)
			exit_code = state.exit_code
			timed_out = true
			break
		}
		time.sleep(2 * time.Millisecond)
	}
	if wth != nil {
		thread.join(wth)
		thread.destroy(wth)
	}
	return exit_code, timed_out, ""
}
