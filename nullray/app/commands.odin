/*
Slash command catalog and help text for the TUI.
*/

package app

import "core:fmt"
import "core:strings"

Slash_Cmd :: struct {
	name: string,
	usage: string,
	help:  string,
}

SLASH_COMMANDS := []Slash_Cmd{
	{"help", "/help", "show commands and shortcuts"},
	{"compact", "/compact", "compact conversation history"},
	{"tools", "/tools", "toggle agent tools"},
	{"reasoning", "/reasoning LEVEL", "set reasoning effort"},
	{"think", "/think LEVEL", "alias for /reasoning"},
	{"sessions", "/sessions", "list saved sessions"},
	{"search", "/search QUERY", "search session names and text"},
	{"resume", "/resume NAME", "open a saved session"},
	{"switch", "/switch NAME", "alias for /resume"},
	{"name", "/name NAME", "rename current session"},
	{"new", "/new [NAME]", "start a new empty session"},
	{"fork", "/fork NAME", "fork current session under a new name"},
	{"ephemeral", "/ephemeral on|off", "toggle session persistence"},
	{"group", "/group NAME|none", "shared context group"},
	{"theme", "/theme NAME", "switch color theme"},
	{"themes", "/themes", "list built-in themes"},
	{"keys", "/keys", "show key bindings"},
	{"mode", "/mode ask|plan|edit", "agent interaction mode"},
	{"perms", "/perms ask|allow|yolo", "shell permission level"},
	{"improve", "/improve", "rewrite draft prompt via model (opt-in)"},
	{"pause", "/pause", "pause running agent after current step"},
	{"stop", "/stop", "stop running agent"},
	{"continue", "/continue [note]", "continue after pause/stop"},
	{"auto", "/auto on|off", "autonomous agent (edit + yolo)"},
	{"secrets", "/secrets path", "allow reading a secret path"},
	{"review", "/review on|off", "end-of-turn review pass"},
	{"allow", "/allow", "approve pending shell command once"},
	{"deny", "/deny", "drop pending shell command"},
	{"undo", "/undo", "undo last agent file write"},
	{"attach", "/attach PATH", "attach a file into the next prompt"},
	{"copy", "/copy", "copy last assistant reply"},
}

slash_matches :: proc(prefix: string, allocator := context.temp_allocator) -> []Slash_Cmd {
	p := strings.trim_space(prefix)
	if !strings.has_prefix(p, "/") {
		return {}
	}
	body := p[1:]
	space := strings.index_byte(body, ' ')
	if space >= 0 {
		return {}
	}
	out := make([dynamic]Slash_Cmd, 0, 8, allocator)
	for cmd in SLASH_COMMANDS {
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
		fmt.sbprintf(&b, "  %-22s %s\n", cmd.usage, cmd.help)
	}
	strings.write_string(&b, "\nClick ? again or press Esc / F1 to close.")
	return strings.to_string(b)
}
