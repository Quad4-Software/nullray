// SPDX-License-Identifier: 0BSD
/*
Slash command catalog, completion, and help text.
*/

package app

import "core:fmt"
import "core:strings"

Slash_Handler :: #type proc(a: ^App, args: string)

Slash_Command :: struct {
	name:  string,
	usage: string,
	help:  string,
	run:   Slash_Handler,
}

SLASH_COMMANDS := []Slash_Command{
	{"help", "/help", "show commands and shortcuts", slash_cmd_help},
	{"?", "/?", "alias for /help", slash_cmd_help},
	{"compact", "/compact", "compact conversation history", slash_cmd_compact},
	{"tools", "/tools", "toggle agent tools", slash_cmd_tools},
	{"reasoning", "/reasoning LEVEL", "set reasoning effort", slash_cmd_reasoning},
	{"think", "/think LEVEL", "alias for /reasoning", slash_cmd_reasoning},
	{"sessions", "/sessions", "list saved sessions", slash_cmd_sessions},
	{"session", "/session", "alias for /sessions", slash_cmd_sessions},
	{"search", "/search QUERY", "search session names and text", slash_cmd_search},
	{"resume", "/resume NAME", "open a saved session", slash_cmd_resume},
	{"switch", "/switch NAME", "alias for /resume", slash_cmd_resume},
	{"name", "/name NAME", "rename current session", slash_cmd_name},
	{"new", "/new [NAME]", "start a new empty session", slash_cmd_new},
	{"fork", "/fork NAME", "fork current session under a new name", slash_cmd_fork},
	{"delete", "/delete NAME", "delete a saved session from disk", slash_cmd_delete},
	{"ephemeral", "/ephemeral on|off", "toggle session persistence", slash_cmd_ephemeral},
	{"group", "/group NAME|none", "shared context group", slash_cmd_group},
	{"theme", "/theme NAME", "switch color theme", slash_cmd_theme},
	{"themes", "/themes", "list built-in themes", slash_cmd_themes},
	{"keys", "/keys", "show key bindings", slash_cmd_keys},
	{"mode", "/mode ask|plan|review|edit", "agent interaction mode", slash_cmd_mode},
	{"approve", "/approve", "approve plan contract and switch to edit", slash_cmd_approve},
	{"status", "/status", "show mode, plan, verify, context chars", slash_cmd_status},
	{"perms", "/perms ask|allow|yolo", "shell permission level", slash_cmd_perms},
	{"improve", "/improve", "rewrite draft prompt via model (opt-in)", slash_cmd_improve},
	{"pause", "/pause", "pause running agent after current step", slash_cmd_pause},
	{"stop", "/stop", "stop running agent", slash_cmd_stop},
	{"cancel", "/cancel", "alias for /stop", slash_cmd_stop},
	{"continue", "/continue [note]", "continue after pause/stop", slash_cmd_continue},
	{"auto", "/auto on|off", "autonomous agent (edit + yolo)", slash_cmd_auto},
	{"secrets", "/secrets path", "allow reading a secret path", slash_cmd_secrets},
	{"hide", "/hide on|off", "hide account balances and credit labels", slash_cmd_hide},
	{"review", "/review on|off", "end-of-turn review pass", slash_cmd_review},
	{"verify", "/verify on|off|CMD", "post-edit verify gate", slash_cmd_verify},
	{"allow", "/allow", "approve pending shell command once", slash_cmd_allow},
	{"deny", "/deny", "drop pending shell command", slash_cmd_deny},
	{"undo", "/undo", "undo last agent file write", slash_cmd_undo},
	{"attach", "/attach PATH", "attach a file into the next prompt", slash_cmd_attach},
	{"copy", "/copy", "copy last assistant reply", slash_cmd_copy},
}

slash_find :: proc(name: string) -> (^Slash_Command, bool) {
	for &cmd in SLASH_COMMANDS {
		if cmd.name == name {
			return &cmd, true
		}
	}
	return nil, false
}

slash_matches :: proc(prefix: string, allocator := context.temp_allocator) -> []Slash_Command {
	p := strings.trim_space(prefix)
	if !strings.has_prefix(p, "/") {
		return {}
	}
	body := p[1:]
	space := strings.index_byte(body, ' ')
	if space >= 0 {
		return {}
	}
	out := make([dynamic]Slash_Command, 0, 8, allocator)
	for cmd in SLASH_COMMANDS {
		if cmd.name == "?" || cmd.name == "session" || cmd.name == "cancel" {
			continue
		}
		if len(body) == 0 || strings.has_prefix(cmd.name, body) {
			append(&out, cmd)
		}
	}
	return out[:]
}

slash_complete :: proc(prefix: string, sel: int) -> (completed: string, ok: bool) {
	matches := slash_matches(prefix)
	if len(matches) == 0 {
		return "", false
	}
	idx := sel
	if idx < 0 {
		idx = 0
	}
	if idx >= len(matches) {
		idx = len(matches) - 1
	}
	return fmt.tprintf("/%s", matches[idx].name), true
}

help_overlay_text :: proc(binds_help: string, allocator := context.allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	strings.write_string(&b, "nullray help\n\n")
	strings.write_string(&b, "Shortcuts\n")
	strings.write_string(&b, binds_help)
	strings.write_string(&b, "\n\nSlash commands\n")
	for cmd in SLASH_COMMANDS {
		if cmd.name == "?" || cmd.name == "session" || cmd.name == "cancel" {
			continue
		}
		fmt.sbprintf(&b, "  %-22s %s\n", cmd.usage, cmd.help)
	}
	strings.write_string(&b, "\nClick ? again or press Esc / F1 to close.")
	return strings.to_string(b)
}
