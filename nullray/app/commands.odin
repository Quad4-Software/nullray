// SPDX-License-Identifier: 0BSD
/*
Slash command catalog, completion, and help text.
*/

package app

import "core:fmt"
import "core:strings"
import "nullray:provider"

Slash_Handler :: #type proc(a: ^App, args: string)

Slash_Command :: struct {
	name:  string,
	usage: string,
	help:  string,
	run:   Slash_Handler,
}

PROVIDER_SLASH_EXTRA := []string{"next", "prev", "setup"}

SLASH_COMMANDS := []Slash_Command{
	{"help", "/help", "show commands and shortcuts", slash_cmd_help},
	{"?", "/?", "alias for /help", slash_cmd_help},
	{"compact", "/compact", "compact conversation history", slash_cmd_compact},
	{"drop", "/drop N", "drop last N user turns (backup saved)", slash_cmd_drop},
	{"tools", "/tools", "toggle agent tools", slash_cmd_tools},
	{"reasoning", "/reasoning LEVEL", "set reasoning effort", slash_cmd_reasoning},
	{"think", "/think LEVEL", "alias for /reasoning", slash_cmd_reasoning},
	{"sessions", "/sessions", "list saved sessions", slash_cmd_sessions},
	{"session", "/session", "alias for /sessions", slash_cmd_sessions},
	{"search", "/search QUERY", "search session names and text", slash_cmd_search},
	{"resume", "/resume NAME", "open a saved session", slash_cmd_resume},
	{"switch", "/switch NAME", "alias for /resume", slash_cmd_resume},
	{"name", "/name NAME [--force]", "rename current session (moves files)", slash_cmd_name},
	{"rename", "/rename NAME [--force]", "alias for /name", slash_cmd_name},
	{"new", "/new [NAME]", "start a new empty session", slash_cmd_new},
	{"fork", "/fork NAME [--force]", "fork current session under a new name", slash_cmd_fork},
	{"delete", "/delete NAME", "delete a saved session from disk", slash_cmd_delete},
	{"ephemeral", "/ephemeral on|off", "toggle session persistence", slash_cmd_ephemeral},
	{"group", "/group NAME|none", "shared context group", slash_cmd_group},
	{"theme", "/theme NAME", "switch color theme", slash_cmd_theme},
	{"themes", "/themes", "list built-in themes", slash_cmd_themes},
	{"skills", "/skills [ID]", "list skills or show one by id", slash_cmd_skills},
	{"skill", "/skill [ID]", "alias for /skills", slash_cmd_skills},
	{"keys", "/keys", "show key bindings", slash_cmd_keys},
	{"setup", "/setup", "provider setup wizard", slash_cmd_setup},
	{"provider", "/provider [ID|next|prev|setup]", "show or switch provider", slash_cmd_provider},
	{"providers", "/providers", "list providers and readiness", slash_cmd_providers},
	{"mode", "/mode ask|plan|review|edit", "agent interaction mode", slash_cmd_mode},
	{"hunt", "/hunt [off|auto|balanced|explore|oracle|adversarial]", "vuln hunt profile and sampling", slash_cmd_hunt},
	{"temp", "/temp [0-2|off]", "sampling temperature override", slash_cmd_temp},
	{"top_p", "/top_p [0-1|off]", "sampling top_p override", slash_cmd_top_p},
	{"model", "/model [NAME|lock|unlock]", "show or set model; lock freezes agent switches", slash_cmd_model},
	{"models", "/models", "list approved models and roles", slash_cmd_models},
	{"agents", "/agents [off|on|list|knowledge|apply ...]", "subagent roster and controls", slash_cmd_agents},
	{"approve", "/approve", "approve plan contract and switch to edit", slash_cmd_approve},
	{"status", "/status", "show mode, plan, verify, tokens, context chars", slash_cmd_status},
	{"ops", "/ops", "show NULLRAY_OPS grants and sandbox extras", slash_cmd_ops},
	{"sandbox", "/sandbox", "alias for /ops", slash_cmd_ops},
	{"usage", "/usage [json|export PATH]", "session token and cost summary", slash_cmd_usage},
	{"perms", "/perms ask|allow|yolo", "shell permission level", slash_cmd_perms},
	{"gate", "/gate 0..3|ask|allow|yolo", "tool capability gate", slash_cmd_gate},
	{"quirks", "/quirks", "list active model output quirks", slash_cmd_quirks},
	{"hooks", "/hooks trust", "re-approve workspace hooks.json", slash_cmd_hooks},
	{"improve", "/improve", "rewrite draft prompt via model (opt-in)", slash_cmd_improve},
	{"pause", "/pause", "pause running agent after current step", slash_cmd_pause},
	{"stop", "/stop", "stop running agent", slash_cmd_stop},
	{"cancel", "/cancel", "alias for /stop", slash_cmd_stop},
	{"continue", "/continue [note]", "continue after pause/stop", slash_cmd_continue},
	{"retry", "/retry", "retry the last user turn after an error", slash_cmd_retry},
	{"reset", "/reset", "wipe sessions and config (needs /reset confirm)", slash_cmd_reset},
	{"auto", "/auto on|off", "autonomous agent (edit + yolo)", slash_cmd_auto},
	{"secrets", "/secrets path", "allow reading a secret path", slash_cmd_secrets},
	{"hide", "/hide on|off", "hide account balances and credit labels", slash_cmd_hide},
	{"review", "/review on|off", "end-of-turn review pass", slash_cmd_review},
	{"verify", "/verify on|off|CMD", "post-edit verify gate", slash_cmd_verify},
	{"allow", "/allow", "approve pending shell command once", slash_cmd_allow},
	{"deny", "/deny", "drop pending shell command", slash_cmd_deny},
	{"undo", "/undo", "undo last agent file write", slash_cmd_undo},
	{"checkpoint", "/checkpoint [list|restore N|diff N]", "list or restore file checkpoints", slash_cmd_checkpoint},
	{"attach", "/attach PATH", "attach a file into the next prompt", slash_cmd_attach},
	{"view", "/view [PATH|auto on|off]", "open a file in the side pane or toggle auto-open", slash_cmd_view},
	{"artifact", "/artifact ID", "open an LID artifact in the side pane", slash_cmd_artifact},
	{"close", "/close", "close the file view pane", slash_cmd_close},
	{"copy", "/copy", "copy selection or last assistant reply", slash_cmd_copy},
}

slash_find :: proc(name: string) -> (^Slash_Command, bool) {
	for &cmd in SLASH_COMMANDS {
		if cmd.name == name {
			return &cmd, true
		}
	}
	return nil, false
}

provider_slash_arg_matches :: proc(arg_prefix: string, allocator := context.temp_allocator) -> []Slash_Command {
	pref := strings.to_lower(strings.trim_space(arg_prefix), context.temp_allocator)
	out := make([dynamic]Slash_Command, 0, 8, allocator)
	for id in provider.PROVIDER_IDS {
		if len(pref) == 0 || strings.has_prefix(id, pref) {
			append(&out, Slash_Command{
				name = id,
				usage = fmt.tprintf("/provider %s", id),
				help = "switch provider",
			})
		}
	}
	for extra in PROVIDER_SLASH_EXTRA {
		if len(pref) == 0 || strings.has_prefix(extra, pref) {
			help := "cycle providers"
			if extra == "setup" {
				help = "open setup wizard"
			} else if extra == "prev" {
				help = "previous provider"
			} else if extra == "next" {
				help = "next provider"
			}
			append(&out, Slash_Command{
				name = extra,
				usage = fmt.tprintf("/provider %s", extra),
				help = help,
			})
		}
	}
	return out[:]
}

slash_matches :: proc(prefix: string, allocator := context.temp_allocator) -> []Slash_Command {
	p := strings.trim_left_space(prefix)
	if !strings.has_prefix(p, "/") {
		return {}
	}
	body := p[1:]
	space := strings.index_byte(body, ' ')
	if space >= 0 {
		name := body[:space]
		rest := strings.trim_left_space(body[space + 1:])
		if name == "provider" && strings.index_byte(rest, ' ') < 0 {
			return provider_slash_arg_matches(rest, allocator)
		}
		return {}
	}
	out := make([dynamic]Slash_Command, 0, 8, allocator)
	for cmd in SLASH_COMMANDS {
		if cmd.name == "?" || cmd.name == "session" || cmd.name == "cancel" || cmd.name == "skill" {
			continue
		}
		if len(body) == 0 || strings.has_prefix(cmd.name, body) {
			append(&out, cmd)
		}
	}
	return out[:]
}

/*
When the user typed /cmd with a trailing space or args, show usage for that command.
*/
slash_arg_hint :: proc(prefix: string, allocator := context.temp_allocator) -> string {
	p := strings.trim_left_space(prefix)
	if !strings.has_prefix(p, "/") {
		return ""
	}
	body := p[1:]
	space := strings.index_byte(body, ' ')
	if space < 0 {
		// Exact command name with no args yet: still show usage if it takes args
		if cmd, ok := slash_find(body); ok && strings.contains(cmd.usage, " ") {
			return fmt.tprintf("%s  %s", cmd.usage, cmd.help)
		}
		return ""
	}
	name := body[:space]
	if name == "provider" {
		// Arg matches draw as a suggestion list instead of a one-line hint.
		return ""
	}
	cmd, ok := slash_find(name)
	if !ok {
		return ""
	}
	return fmt.tprintf("%s  %s", cmd.usage, cmd.help)
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
	cmd := matches[idx]
	p := strings.trim_left_space(prefix)
	if strings.has_prefix(p, "/provider") {
		body := p[1:]
		if strings.index_byte(body, ' ') >= 0 {
			return fmt.tprintf("/provider %s", cmd.name), true
		}
	}
	if strings.contains(cmd.usage, " ") {
		return fmt.tprintf("/%s ", cmd.name), true
	}
	return fmt.tprintf("/%s", cmd.name), true
}

help_overlay_text :: proc(binds_help: string, allocator := context.allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	strings.write_string(&b, "nullray help\n\n")
	strings.write_string(&b, "Shortcuts\n")
	strings.write_string(&b, binds_help)
	strings.write_string(&b, "\n\nSlash commands\n")
	for cmd in SLASH_COMMANDS {
		if cmd.name == "?" || cmd.name == "session" || cmd.name == "cancel" || cmd.name == "skill" {
			continue
		}
		fmt.sbprintf(&b, "  %-22s %s\n", cmd.usage, cmd.help)
	}
	strings.write_string(&b, "\nClick ? again or press Esc / F1 to close.")
	return strings.to_string(b)
}
