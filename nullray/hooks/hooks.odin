// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
User hook loading and bounded subprocess execution.

Hook JSON protocol: each command in hooks.json runs as sh -c <cmd> with the
hook context on stdin: {"event":"<Event>","tool":"<name>","payload":"..."}.
Exit 2 blocks (PreToolUse, UserPromptSubmit, SubagentStart). Timeout is 5s
(NULLRAY_HOOK_TIMEOUT_MS). Hook stdout is captured (64KB cap); JSON lines
there can answer:
  {"decision":"allow"}                       PermissionRequest allow
  {"decision":"deny","reason":"..."}         PermissionRequest deny (also
                                             fires PermissionDenied)
  {"rewrite":{...args...}}                   PreToolUse: replace call args
  {"decision":"rewrite","args":{...}}        wholesale (no merge)
All other events are notification-only.
*/

package hooks

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "nullray:constants"
import "nullray:crash"
import "nullray:sandbox"

Event :: enum {
	PreToolUse,
	PostToolUse,
	SessionStart,
	SessionEnd,
	Stop,
	PreCommit,
	UserPromptSubmit,
	PermissionRequest,
	PermissionDenied,
	SubagentStart,
	SubagentStop,
	Notification,
}

Hook_File :: struct {
	pre_tool_use:       []string `json:"PreToolUse"`,
	post_tool_use:      []string `json:"PostToolUse"`,
	session_start:      []string `json:"SessionStart"`,
	session_end:        []string `json:"SessionEnd"`,
	stop:               []string `json:"Stop"`,
	pre_commit:         []string `json:"PreCommit"`,
	user_prompt_submit: []string `json:"UserPromptSubmit"`,
	permission_request: []string `json:"PermissionRequest"`,
	permission_denied:  []string `json:"PermissionDenied"`,
	subagent_start:     []string `json:"SubagentStart"`,
	subagent_stop:      []string `json:"SubagentStop"`,
	notification:       []string `json:"Notification"`,
}

@(private)
g_untrusted_warned: bool

Result :: struct {
	blocked: bool,
	message: string,
	// PermissionRequest: "allow" or "deny" when a hook answered on stdout.
	// Empty means no hook answered and the normal prompt flow applies.
	decision: string,
	// Optional reason string a deny decision carried.
	reason: string,
	// PreToolUse: replacement args JSON object from a rewrite decision.
	// Replaces the tool call args wholesale; no merge is performed.
	rewrite_args: string,
}

result_destroy :: proc(res: ^Result, allocator := context.allocator) {
	if res == nil {
		return
	}
	delete(res.message, allocator)
	delete(res.decision, allocator)
	delete(res.reason, allocator)
	delete(res.rewrite_args, allocator)
	res^ = {}
}

/*
Trust-gated workspace .nullray config files. Each one lets a cloned repo
steer the agent (hooks run shell commands, model_profiles force temperature
and prompt tier, harnesses pick binaries and flags), so first sight or any
content change requires an explicit /hooks trust approval.
*/
@(private)
hooks_workspace_files :: proc() -> []string {
	st := sandbox.state()
	workspace := ""
	if st != nil {
		workspace = st.workspace
	}
	if len(workspace) == 0 {
		workspace, _ = os.get_working_directory(context.temp_allocator)
	}
	names := []string{constants.HOOKS_FILE, constants.MODEL_PROFILES_FILE, constants.HARNESSES_FILE}
	out := make([dynamic]string, 0, len(names), context.temp_allocator)
	for name in names {
		if p, err := filepath.join({workspace, ".nullray", name}, context.temp_allocator); err == nil {
			append(&out, p)
		}
	}
	return out[:]
}

/*
Approve every gated workspace file present under .nullray: records the live
{mtime_ns, size} of each into <config dir>/hooks_trusted.json; absent files
are skipped because there is nothing to approve. The persisted record
survives restarts and also covers later sessions on the same workspace.
*/
hooks_trust_workspace :: proc() -> bool {
	ok := false
	for path in hooks_workspace_files() {
		if _, err := os.stat(path, context.temp_allocator); err != nil {
			continue
		}
		if !trust_grant_file(path) {
			return false
		}
		ok = true
	}
	return ok
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
	crash.logf("hooks.run event=%s tool=%s", event_name(event), tool_name)
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
	if blocked, msg := hooks_workspace_blocked(allocator); blocked {
		if !g_untrusted_warned {
			g_untrusted_warned = true
		// Untrusted workspace file: the hooks in it simply do not run.
		// The operation itself is not blocked - hooks are a gate, not the
		// permission system - but the message rides along for callers that
		// surface Result.message.
			fmt.eprintf("nullray: %s; workspace hooks skipped\n", msg)
		}
		return Result{message = msg}
	}
	local_path, _ := filepath.join({workspace, ".nullray", constants.HOOKS_FILE}, context.temp_allocator)
	paths := []string{global_path, local_path}
	out: Result
	for path in paths {
		res := run_file(path, event, tool_name, payload, allocator)
		if res.blocked {
			result_destroy(&out, allocator)
			return res
		}
		// First answering hook wins; later files only run when nothing
		// decided yet so one hook cannot silently undo a rewrite/deny.
		if len(out.decision) == 0 && len(out.rewrite_args) == 0 {
			result_destroy(&out, allocator)
			out = res
		} else {
			result_destroy(&res, allocator)
		}
	}
	return out
}

/*
True while every gated workspace .nullray file (hooks.json,
model_profiles.json, harnesses.json) passes the mtime trust check (absent or
unchanged since approval). Script tools and harnesses.json reuse this gate
because a workspace can ship arbitrary executables and binary picks the same
way it ships hook commands: all must follow the /hooks trust handoff.
*/
hooks_workspace_trusted :: proc() -> bool {
	blocked, msg := hooks_workspace_blocked(context.temp_allocator)
	delete(msg, context.temp_allocator)
	return !blocked
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
	case .UserPromptSubmit:
		return "UserPromptSubmit"
	case .PermissionRequest:
		return "PermissionRequest"
	case .PermissionDenied:
		return "PermissionDenied"
	case .SubagentStart:
		return "SubagentStart"
	case .SubagentStop:
		return "SubagentStop"
	case .Notification:
		return "Notification"
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
	if hooks_file_trusted(path) {
		return false, ""
	}
	return true, strings.clone(
		fmt.tprintf("workspace %s not trusted (run /hooks trust)", filepath.base(path)),
		allocator,
	)
}

// Gate over every gated workspace file, not just hooks.json: an untrusted
// model_profiles.json or harnesses.json must not run beside trusted hooks.
@(private)
hooks_workspace_blocked :: proc(allocator := context.allocator) -> (blocked: bool, message: string) {
	for path in hooks_workspace_files() {
		if b, m := local_hooks_trust_check(path, allocator); b {
			return true, m
		}
	}
	return false, ""
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
	case .UserPromptSubmit:
		return cfg.user_prompt_submit
	case .PermissionRequest:
		return cfg.permission_request
	case .PermissionDenied:
		return cfg.permission_denied
	case .SubagentStart:
		return cfg.subagent_start
	case .SubagentStop:
		return cfg.subagent_stop
	case .Notification:
		return cfg.notification
	}
	return nil
}

@(private)
run_file :: proc(path: string, event: Event, tool_name, payload: string, allocator := context.allocator) -> Result {
	data, rerr := os.read_entire_file(path, context.temp_allocator)
	if rerr != nil {
		if os.is_file(path) {
			crash.logf("hook file unreadable %s: %v", path, rerr)
		}
		return {}
	}
	crash.logf("hook file read %s bytes=%d", path, len(data))
	cfg: Hook_File
	if jerr := json.unmarshal(data, &cfg, .JSON, context.temp_allocator); jerr != nil {
		return Result{message = fmt.aprintf("hook config parse failed for %s: %v", path, jerr, allocator = allocator)}
	}
	ib: strings.Builder
	strings.builder_init(&ib, context.temp_allocator)
	strings.write_string(&ib, `{"event":`)
	write_json_string(&ib, event_name(event))
	strings.write_string(&ib, `,"tool":`)
	write_json_string(&ib, tool_name)
	strings.write_string(&ib, `,"payload":`)
	write_json_string(&ib, payload)
	strings.write_byte(&ib, '}')
	input := strings.to_string(ib)
	out: Result
	cmds := commands_for(&cfg, event)
	crash.logf("hook cmds for %s: %d", event_name(event), len(cmds))
	for command in cmds {
		exit_code, timed_out, stdout, err := run_command(command, input)
		crash.logf("hook cmd exit=%d timeout=%v err=%q out=%q", exit_code, timed_out, err, stdout)
		if err != "" {
			continue
		}
		if timed_out {
			continue
		}
		apply_hook_output(event, stdout, &out, allocator)
		if exit_code == 2 {
			result_destroy(&out, allocator)
			return Result{
				blocked = true,
				message = fmt.aprintf("%s hook blocked %s", event_name(event), tool_name, allocator = allocator),
			}
		}
	}
	return out
}

