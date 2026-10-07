// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
User script tools: executable files that become tools (the shell-native
equivalent of OpenCode .opencode/tools). Scanned at registry init:

  <config>/tools/              user level, always trusted (user-owned dir)
  <workspace>/.nullray/tools/  workspace level, only when hooks trust holds
                               (hooks_workspace_trusted) or NULLRAY_SCRIPT_TOOLS=1

Workspace scripts are gated on the hooks trust handoff because a checked-out
repo can ship arbitrary executables the same way it ships hooks.json commands.

Layout per tool:
  <name>.sh | .bash | .py | .js   run through the matching interpreter
  <name>                          extensionless executable (POSIX only)
  <name>.md            optional description (first paragraph)
  <name>.schema.json   optional JSON schema for args
  <name>.meta          optional kind hint: read | write | shell (default shell)

POSIX requires the executable bit on the script file itself.

Execution protocol:
  stdin + NULLRAY_TOOL_ARGS env carry the args JSON object.
  stdout becomes the tool result (capped at MAX_SHELL_OUTPUT_BYTES, larger
  output flows through the normal artifact offload path).
  On nonzero exit or timeout a "exit_code=N" line is prepended and stderr is
  appended as a "stderr:" suffix.
  Timeout: 60s, killed via the shared process-tree helper (Esc cancels).

Script tools are registered AFTER builtins, a name collision with an existing
tool is skipped with a stderr warn so a script can never silently shadow a
builtin or an earlier-registered script (user dir wins over workspace).

Hook JSON protocol (shared with hooks.json handlers in nullray/hooks):
  stdin: {"event":"<Event>","tool":"<name>","payload":"..."}
  exit 2:  block (PreToolUse, UserPromptSubmit, SubagentStart)
  stdout decision lines:
    {"decision":"allow"}                        PermissionRequest allow
    {"decision":"deny","reason":"..."}          PermissionRequest deny
    {"rewrite":{...args...}}                    PreToolUse arg rewrite
    {"decision":"rewrite","args":{...}}         same, replaces args wholesale
*/

package tools

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:path/filepath"
import "core:strings"
import "core:thread"
import "core:time"
import "nullray:constants"
import "nullray:crash"
import "nullray:hooks"
import "nullray:sandbox"
import "nullray:subagent"

Script_Tool :: struct {
	name:   string,
	path:   string,
	interp: string,
	desc:   string,
	schema: string,
	kind:   Tool_Kind,
}

SCRIPT_TOOL_TIMEOUT_MS :: 60_000

DEFAULT_SCRIPT_SCHEMA :: `{"type":"object","properties":{"input":{"type":"string"}}}`

register_script_tools :: proc(r: ^Registry) {
	if r == nil {
		return
	}
	// User dir first so user-owned tools win name ties over workspace ones.
	if cfg := sandbox.resolve_config_dir(context.temp_allocator); len(cfg) > 0 {
		if dir, jerr := filepath.join({cfg, "tools"}, context.temp_allocator); jerr == nil {
			script_tools_scan_dir(r, dir)
		}
	}
	if !script_tools_workspace_enabled() {
		return
	}
	ws := workspace_root(context.temp_allocator)
	if dir, jerr := filepath.join({ws, constants.SCRIPTTOOLS_DIR}, context.temp_allocator); jerr == nil {
		script_tools_scan_dir(r, dir)
	}
}

script_tools_destroy :: proc(r: ^Registry) {
	if r == nil {
		return
	}
	for st in r.script_tools {
		script_tool_free(st)
	}
	delete(r.script_tools)
	r.script_tools = nil
}

@(private)
script_tool_free :: proc(st: ^Script_Tool) {
	if st == nil {
		return
	}
	delete(st.name)
	delete(st.path)
	delete(st.interp)
	delete(st.desc)
	delete(st.schema)
	free(st)
}

@(private)
script_tools_workspace_enabled :: proc() -> bool {
	if hooks.hooks_workspace_trusted() {
		return true
	}
	if v, ok := os.lookup_env(constants.ENV_SCRIPT_TOOLS, context.temp_allocator); ok {
		switch strings.to_lower(strings.trim_space(v)) {
		case "1", "true", "yes", "on":
			return true
		}
	}
	return false
}

@(private)
script_tools_scan_dir :: proc(r: ^Registry, dir: string) {
	crash.logf("script tools scan %s", dir)
	if len(dir) == 0 || !os.is_directory(dir) {
		crash.logf("script tools dir missing %s", dir)
		return
	}
	dh, herr := os.open(dir)
	if herr != nil {
		return
	}
	defer os.close(dh)
	infos, rerr := os.read_dir(dh, -1, context.temp_allocator)
	if rerr != nil {
		return
	}
	// Sorted registration keeps tools JSON byte-stable across runs so
	// provider prefix caches stay warm.
	slice.sort_by(infos[:], proc(a, b: os.File_Info) -> bool {
		return strings.compare(a.name, b.name) < 0
	})
	for info in infos {
		if info.type != .Regular {
			continue
		}
		name, interp, ok := script_tool_candidate(info)
		if !ok || !script_tool_name_ok(name) {
			continue
		}
		if _, found := registry_find(r, name); found {
			fmt.eprintf("nullray: script tool %s skipped: name already registered\n", name)
			continue
		}
		path, perr := filepath.join({dir, info.name}, context.temp_allocator)
		if perr != nil {
			continue
		}
		crash.logf("script tool register %s -> %s", name, path)
		st := new(Script_Tool)
		st.name = strings.clone(name)
		st.path = strings.clone(path)
		st.interp = strings.clone(interp)
		st.desc = script_tool_sidecar_desc(dir, name)
		st.schema = script_tool_sidecar_schema(dir, name)
		st.kind = script_tool_sidecar_kind(dir, name)
		append(&r.script_tools, st)
		registry_register(r, Tool{
			name = st.name,
			description = st.desc,
			schema_json = st.schema,
			kind = st.kind,
			run_named = script_tool_exec,
			user = st,
		})
	}
}

@(private)
script_tool_name_ok :: proc(name: string) -> bool {
	if len(name) == 0 || name[0] == '-' || name[0] == '_' {
		return false
	}
	for c in name {
		switch {
		case c >= 'a' && c <= 'z', c >= 'A' && c <= 'Z', c >= '0' && c <= '9':
		case c == '_' || c == '-':
		case:
			return false
		}
	}
	return true
}

// Split a candidate filename into tool name + interpreter, or ok=false.
@(private)
script_tool_candidate :: proc(info: os.File_Info) -> (name: string, interp: string, ok: bool) {
	base := info.name
	switch {
	case strings.has_suffix(base, ".sh"):
		name, interp = base[:len(base) - 3], "/bin/sh"
	case strings.has_suffix(base, ".bash"):
		name, interp = base[:len(base) - 5], "/bin/sh"
	case strings.has_suffix(base, ".py"):
		name, interp = base[:len(base) - 3], "/usr/bin/python3"
	case strings.has_suffix(base, ".js"):
		name, interp = base[:len(base) - 3], "node"
	case:
		// Extensionless must be directly executable, no exec bit on Windows
		// and no shebang runner, so extensionless is POSIX-only.
		when ODIN_OS == .Windows {
			return "", "", false
		} else {
			if strings.contains(base, ".") {
				return "", "", false
			}
			name, interp = base, ""
		}
	}
	when ODIN_OS == .Windows {
		// Interpreter names resolve through PATH there.
		switch interp {
		case "/bin/sh":
			interp = "bash.exe"
		case "/usr/bin/python3":
			interp = "python"
		}
		return name, interp, true
	}
	// POSIX: the script file itself must carry the executable bit even when
	// an interpreter would technically run it, that is the trust contract.
	return name, interp, info.mode & os.Permissions_Execute_All != {}
}

@(private)
script_tool_sidecar_desc :: proc(dir, name: string) -> string {
	side := strings.concatenate({name, ".md"}, context.temp_allocator)
	if path, perr := filepath.join({dir, side}, context.temp_allocator); perr == nil {
		if data, rerr := os.read_entire_file(path, context.temp_allocator); rerr == nil {
			if d := script_first_paragraph(string(data)); len(d) > 0 {
				return strings.clone(d)
			}
		}
	}
	return strings.clone(fmt.tprintf("user script tool %s", name))
}

@(private)
script_first_paragraph :: proc(text: string) -> string {
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	rest := text
	wrote := false
	for line in strings.split_lines_iterator(&rest) {
		t := strings.trim_space(line)
		if len(t) == 0 {
			if wrote {
				break
			}
			continue
		}
		if wrote {
			strings.write_byte(&b, ' ')
		}
		strings.write_string(&b, t)
		wrote = true
	}
	out := strings.to_string(b)
	if len(out) > 240 {
		out = out[:240]
	}
	return out
}

@(private)
script_tool_sidecar_schema :: proc(dir, name: string) -> string {
	side := strings.concatenate({name, ".schema.json"}, context.temp_allocator)
	if path, perr := filepath.join({dir, side}, context.temp_allocator); perr == nil {
		if data, rerr := os.read_entire_file(path, context.temp_allocator); rerr == nil {
			text := strings.trim_space(string(data))
			if v, jerr := json.parse_string(text, .JSON, allocator = context.temp_allocator); jerr == nil {
				if _, is_obj := v.(json.Object); is_obj {
					return strings.clone(text)
				}
			}
		}
	}
	return strings.clone(DEFAULT_SCRIPT_SCHEMA)
}

// <name>.meta kind hint: first token, read|write|shell (or kind=<x>). Default shell.
@(private)
script_tool_sidecar_kind :: proc(dir, name: string) -> Tool_Kind {
	side := strings.concatenate({name, ".meta"}, context.temp_allocator)
	path, perr := filepath.join({dir, side}, context.temp_allocator)
	if perr != nil {
		return .Shell
	}
	data, rerr := os.read_entire_file(path, context.temp_allocator)
	if rerr != nil {
		return .Shell
	}
	tok := strings.trim_space(string(data))
	if eq := strings.index_byte(tok, '='); eq >= 0 {
		tok = strings.trim_space(tok[eq + 1:])
	}
	if nl := strings.index_byte(tok, '\n'); nl >= 0 {
		tok = tok[:nl]
	}
	tok = strings.trim_space(tok)
	switch strings.to_lower(tok, context.temp_allocator) {
	case "read", "ro":
		return .Read
	case "write":
		return .Write
	case "shell":
		return .Shell
	}
	return .Shell
}
