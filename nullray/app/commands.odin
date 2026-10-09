// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Slash command catalog, completion, and help text.
*/

package app

import "core:fmt"
import "core:strings"
import "nullray:provider"
import "nullray:store"

Slash_Handler :: #type proc(a: ^App, args: string)

Slash_Command :: struct {
	name:  string,
	usage: string,
	help:  string,
	run:   Slash_Handler,
}

PROVIDER_SLASH_EXTRA := []string{"next", "prev", "setup"}

MODEL_SLASH_EXTRA := []string{"lock", "unlock"}

MODEL_SLASH_ARG_LIMIT :: 12

SLASH_COMMANDS := []Slash_Command{
	{"help", "/help", "show commands and shortcuts", slash_cmd_help},
	{"?", "/?", "alias for /help", slash_cmd_help},
	{"compact", "/compact", "compact conversation history", slash_cmd_compact},
	{"rewind", "/rewind [N]", "rewind N user turns, restore files, summarize from here", slash_cmd_rewind},
	{"drop", "/drop N", "drop last N user turns (backup saved)", slash_cmd_drop},
	{"tools", "/tools", "toggle agent tools", slash_cmd_tools},
	{"expand", "/expand", "expand or collapse all tool calls", slash_cmd_expand},
	{"history", "/history", "scrollable session history incl. thinking", slash_cmd_history},
	{"reasoning", "/reasoning LEVEL", "set reasoning effort", slash_cmd_reasoning},
	{"think", "/think LEVEL", "alias for /reasoning", slash_cmd_reasoning},
	{"sessions", "/sessions", "list saved sessions", slash_cmd_sessions},
	{"session", "/session", "alias for /sessions", slash_cmd_sessions},
	{"search", "/search QUERY", "search session names and text", slash_cmd_search},
	{"resume", "/resume NAME", "open a saved session", slash_cmd_resume},
	{"switch", "/switch NAME", "alias for /resume", slash_cmd_resume},
	{"name", "/name NAME [--force]", "rename current session (moves files)", slash_cmd_name},
	{"rename", "/rename NAME [--force]", "alias for /name", slash_cmd_name},
	{"new", "/new [NAME]", "start a new session in a new tab", slash_cmd_new},
	{"tab", "/tab [list|new|open|next|prev|close [NAME|N]|N]", "manage session tabs", slash_cmd_tab},
	{"fork", "/fork NAME [--force]", "fork current session under a new name", slash_cmd_fork},
	{"delete", "/delete [NAME|tab|current]", "delete session (bare = current tab/session)", slash_cmd_delete},
	{"rm", "/rm [NAME|tab|current]", "alias for /delete", slash_cmd_delete},
	{"ephemeral", "/ephemeral on|off", "toggle session persistence", slash_cmd_ephemeral},
	{"encrypt", "/encrypt [on KEY|off|status]", "seal session transcripts at rest", slash_cmd_encrypt},
	{"scrub", "/scrub [all|last|matching NEEDLE]", "redact or forget session content", slash_cmd_scrub},
	{"demo", "/demo malleable", "smoke show_view/set_tui privacy paths", slash_cmd_demo},
	{"group", "/group NAME|none", "shared context group", slash_cmd_group},
	{"theme", "/theme NAME [global|session]", "switch color theme (default saves global)", slash_cmd_theme},
	{"themes", "/themes", "list built-in themes", slash_cmd_themes},
	{"tui", "/tui [get|reset|lock|unlock|NAME]", "malleable TUI theme (session/global)", slash_cmd_tui},
	{"skills", "/skills [ID]", "list skills or show one by id", slash_cmd_skills},
	{"skill", "/skill [ID]", "alias for /skills", slash_cmd_skills},
	{"learn", "/learn ID [description]", "save a compact skill from last reply", slash_cmd_learn},
	{"canvas", "/canvas list|open|save|rm", "persist and reopen agent panel UIs", slash_cmd_canvas},
	{"keys", "/keys", "show key bindings", slash_cmd_keys},
	{"setup", "/setup", "provider setup wizard", slash_cmd_setup},
	{"provider", "/provider [ID|next|prev|setup]", "show or switch provider", slash_cmd_provider},
	{"providers", "/providers", "list providers and readiness", slash_cmd_providers},
	{"mode", "/mode ask|plan|review|edit|orchestrate", "agent interaction mode", slash_cmd_mode},
	{"hunt", "/hunt [off|auto|balanced|explore|oracle|adversarial]", "vuln hunt profile and sampling", slash_cmd_hunt},
	{"temp", "/temp [0-2|off]", "sampling temperature override", slash_cmd_temp},
	{"top_p", "/top_p [0-1|off]", "sampling top_p override", slash_cmd_top_p},
	{"model", "/model [NAME|lock|unlock]", "show or set model; lock freezes agent switches", slash_cmd_model},
	{"models", "/models [policy]", "list provider models (policy: /models policy)", slash_cmd_models},
	{"agents", "/agents [off|on|list|knowledge|apply|worktree ...]", "subagent roster and controls", slash_cmd_agents},
	{"todo", "/todo", "show session task list", slash_cmd_todo},
	{"schedule", "/schedule [list|cancel ID|cancel all]", "scheduled prompts", slash_cmd_schedule},
	{"watch", "/watch [list|add <spec> <task>|show ID|rm ID]", "standing watches that notify on new hits", slash_cmd_watch},
	{"loop", "/loop <every> <prompt>", "recurring prompt in this session", slash_cmd_loop},
	{"remind", "/remind <in> <text>", "one-shot reminder prompt", slash_cmd_remind},
	{"approve", "/approve", "approve plan contract and switch to edit", slash_cmd_approve},
	{"status", "/status", "show mode, plan, verify, tokens, context chars", slash_cmd_status},
	{"context", "/context", "per-category context char and token estimate", slash_cmd_context},
	{"steps", "/steps [N|auto|default]", "max agent tool steps per turn (default 24, auto 80)", slash_cmd_steps},
	{"ops", "/ops", "show NULLRAY_OPS grants and sandbox extras", slash_cmd_ops},
	{"sandbox", "/sandbox", "alias for /ops", slash_cmd_ops},
	{"usage", "/usage [json|export PATH]", "session token and cost summary", slash_cmd_usage},
	{"perms", "/perms ask|allow|yolo", "shell permission level", slash_cmd_perms},
	{"gate", "/gate 0..3|ask|allow|yolo", "tool capability gate", slash_cmd_gate},
	{"quirks", "/quirks", "list active model output quirks", slash_cmd_quirks},
	{"hooks", "/hooks trust", "re-approve workspace hooks.json", slash_cmd_hooks},
	{"distill", "/distill", "distill turn history into experience.md", slash_cmd_distill},
	{"improve", "/improve", "rewrite draft prompt via model (opt-in)", slash_cmd_improve},
	{"pause", "/pause", "pause running agent after current step", slash_cmd_pause},
	{"stop", "/stop", "stop running agent", slash_cmd_stop},
	{"cancel", "/cancel", "alias for /stop", slash_cmd_stop},
	{"continue", "/continue [note]", "continue after pause/stop", slash_cmd_continue},
	{"retry", "/retry", "retry the last user turn after an error", slash_cmd_retry},
	{"reset", "/reset", "wipe sessions and config (needs /reset confirm)", slash_cmd_reset},
	{"auto", "/auto on|off", "autonomous agent (edit + yolo)", slash_cmd_auto},
	{"secrets", "/secrets path", "allow reading a secret path", slash_cmd_secrets},
	{"secret", "/secret list|set|ask|forget|has|clear|backend", "agent vault secrets (values hidden; optional keyring)", slash_cmd_secret},
	{"key", "/key …", "alias for /secret", slash_cmd_secret},
	{"token", "/token …", "alias for /secret", slash_cmd_secret},
	{"hide", "/hide on|off", "hide account balances and credit labels", slash_cmd_hide},
	{"review", "/review on|off|local [scope]", "end-of-turn review or local VCS review bot", slash_cmd_review},
	{"verify", "/verify on|off|CMD", "post-edit verify gate", slash_cmd_verify},
	{"allow", "/allow", "approve pending shell command once", slash_cmd_allow},
	{"deny", "/deny", "drop pending shell command", slash_cmd_deny},
	{"undo", "/undo", "undo last agent file write", slash_cmd_undo},
	{"checkpoint", "/checkpoint [list|restore N|diff N]", "list or restore file checkpoints", slash_cmd_checkpoint},
	{"attach", "/attach PATH", "attach text or media into the next prompt", slash_cmd_attach},
	{"view", "/view [PATH|auto on|off]", "open a file in the side pane or toggle auto-open", slash_cmd_view},
	{"artifact", "/artifact ID", "open an LID artifact in the side pane", slash_cmd_artifact},
	{"close", "/close [tab|view|NAME|N]", "close view, current tab, or named tab", slash_cmd_close},
	{"copy", "/copy", "copy selection or last assistant reply", slash_cmd_copy},
}

TAB_SLASH_EXTRA := []string{"list", "new", "open", "next", "prev", "close", "n", "p", "w"}
CANVAS_SLASH_EXTRA := []string{"list", "open", "save", "rm", "delete"}

CLOSE_SLASH_EXTRA := []string{"tab", "view", "current", "this"}

DELETE_SLASH_EXTRA := []string{"current", "this", "tab", "."}

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

@(private)
model_arg_push :: proc(out: ^[dynamic]Slash_Command, id, current: string) {
	help := "switch model"
	if id == current {
		help = "current model"
	}
	append(out, Slash_Command{
		name = id,
		usage = fmt.tprintf("/model %s", id),
		help = help,
	})
}

// /model arg suggestions. Prefix hits rank above substring hits, the current
// model surfaces first via catalog_view ordering, extras trail the list.
model_slash_arg_matches :: proc(arg_prefix: string, allocator := context.temp_allocator) -> []Slash_Command {
	pref := strings.to_lower(strings.trim_space(arg_prefix), context.temp_allocator)
	view := provider.catalog_view(context.temp_allocator)
	out := make([dynamic]Slash_Command, 0, MODEL_SLASH_ARG_LIMIT, allocator)
	for id in view.ids {
		if len(out) >= MODEL_SLASH_ARG_LIMIT {
			break
		}
		if len(pref) == 0 || strings.has_prefix(strings.to_lower(id, context.temp_allocator), pref) {
			model_arg_push(&out, id, view.current)
		}
	}
	for id in view.ids {
		if len(out) >= MODEL_SLASH_ARG_LIMIT {
			break
		}
		low := strings.to_lower(id, context.temp_allocator)
		if len(pref) > 0 && !strings.has_prefix(low, pref) && strings.contains(low, pref) {
			model_arg_push(&out, id, view.current)
		}
	}
	for extra in MODEL_SLASH_EXTRA {
		if len(out) >= MODEL_SLASH_ARG_LIMIT {
			break
		}
		if len(pref) == 0 || strings.has_prefix(extra, pref) {
			help := "freeze model switches"
			if extra == "unlock" {
				help = "release the model lock"
			}
			append(&out, Slash_Command{
				name = extra,
				usage = fmt.tprintf("/model %s", extra),
				help = help,
			})
		}
	}
	return out[:]
}

/*
Expand a typed /model arg to the full catalog id when it is a unique prefix
of exactly one known id. Exact ids and ambiguous or unknown args pass through.
*/
catalog_expand_unique :: proc(arg: string, allocator := context.temp_allocator) -> string {
	view := provider.catalog_view(allocator)
	found := ""
	count := 0
	pref := strings.to_lower(arg, allocator)
	for id in view.ids {
		if id == arg {
			return arg
		}
		if strings.has_prefix(strings.to_lower(id, allocator), pref) {
			count += 1
			found = id
		}
	}
	if count == 1 {
		return found
	}
	return arg
}

slash_matches :: proc(prefix: string, allocator := context.temp_allocator, a: ^App = nil) -> []Slash_Command {
	p := strings.trim_left_space(prefix)
	if !strings.has_prefix(p, "/") {
		return {}
	}
	body := p[1:]
	space := strings.index_byte(body, ' ')
	if space >= 0 {
		name := body[:space]
		rest := strings.trim_left_space(body[space + 1:])
		// Single-token arg completion (no nested space yet).
		if strings.index_byte(rest, ' ') < 0 {
			switch name {
			case "provider":
				return provider_slash_arg_matches(rest, allocator)
			case "model":
				return model_slash_arg_matches(rest, allocator)
			case "tab":
				return tab_slash_arg_matches(a, rest, allocator)
			case "canvas":
				return canvas_slash_arg_matches(rest, allocator)
			case "close":
				return close_slash_arg_matches(a, rest, allocator)
			case "delete", "rm":
				return delete_slash_arg_matches(a, rest, allocator)
			case "resume", "switch", "fork", "name", "rename":
				return session_name_slash_arg_matches(rest, allocator)
			}
		} else if name == "tab" || name == "close" || name == "delete" || name == "rm" {
			// Second token: /tab close <name>, /close tab <name>, /delete tab <name>
			fields := strings.fields(rest, context.temp_allocator)
			if len(fields) == 2 {
				sub := strings.to_lower(fields[0], context.temp_allocator)
				pref := fields[1]
				if (name == "tab" && sub == "close") ||
				   (name == "close" && (sub == "tab" || sub == "view")) ||
				   ((name == "delete" || name == "rm") && sub == "tab") {
					if sub == "view" {
						return {}
					}
					return open_tab_name_matches(a, pref, allocator)
				}
			}
		}
		return {}
	}
	out := make([dynamic]Slash_Command, 0, 8, allocator)
	for cmd in SLASH_COMMANDS {
		if cmd.name == "?" || cmd.name == "session" || cmd.name == "cancel" || cmd.name == "skill" || cmd.name == "rm" {
			continue
		}
		if len(body) == 0 || strings.has_prefix(cmd.name, body) {
			append(&out, cmd)
		}
	}
	for c in custom_command_matches(body, allocator) {
		append(&out, c)
	}
	return out[:]
}

// Open-tab names (and 1-based indexes) for completion. a may be nil in pure
// unit tests; then only static extras are offered.
open_tab_name_matches :: proc(a: ^App, pref: string, allocator := context.temp_allocator) -> []Slash_Command {
	out := make([dynamic]Slash_Command, 0, 8, allocator)
	p := strings.to_lower(strings.trim_space(pref), context.temp_allocator)
	if a != nil {
		for t, i in a.tabs {
			name := t.sess.name
			if len(name) == 0 {
				continue
			}
			num := fmt.tprintf("%d", i + 1)
			name_l := strings.to_lower(name, context.temp_allocator)
			if len(p) == 0 || strings.has_prefix(name_l, p) || strings.has_prefix(num, p) {
				help := "open tab"
				if i == a.active_tab {
					help = "current tab"
				}
				append(&out, Slash_Command{
					name = name,
					usage = name,
					help = help,
				})
			}
		}
	}
	return out[:]
}

tab_slash_arg_matches :: proc(a: ^App, pref: string, allocator := context.temp_allocator) -> []Slash_Command {
	out := make([dynamic]Slash_Command, 0, 12, allocator)
	p := strings.to_lower(strings.trim_space(pref), context.temp_allocator)
	for extra in TAB_SLASH_EXTRA {
		if len(p) == 0 || strings.has_prefix(extra, p) {
			help := "tab action"
			switch extra {
			case "list":
				help = "list open tabs"
			case "new":
				help = "new tab"
			case "open":
				help = "open saved session in a tab"
			case "next", "n":
				help = "next tab"
			case "prev", "p":
				help = "previous tab"
			case "close", "w":
				help = "close current tab"
			}
			append(&out, Slash_Command{
				name = extra,
				usage = fmt.tprintf("/tab %s", extra),
				help = help,
			})
		}
	}
	// Also offer open tab names/indexes for jump and close.
	for m in open_tab_name_matches(a, pref, context.temp_allocator) {
		append(&out, Slash_Command{
			name = m.name,
			usage = fmt.tprintf("/tab %s", m.name),
			help = m.help,
		})
	}
	return out[:]
}

canvas_slash_arg_matches :: proc(pref: string, allocator := context.temp_allocator) -> []Slash_Command {
	out := make([dynamic]Slash_Command, 0, 8, allocator)
	p := strings.to_lower(strings.trim_space(pref), context.temp_allocator)
	for extra in CANVAS_SLASH_EXTRA {
		if len(p) == 0 || strings.has_prefix(extra, p) {
			append(&out, Slash_Command{
				name = extra,
				usage = fmt.tprintf("/canvas %s", extra),
				help = "canvas action",
			})
		}
	}
	return out[:]
}

close_slash_arg_matches :: proc(a: ^App, pref: string, allocator := context.temp_allocator) -> []Slash_Command {
	out := make([dynamic]Slash_Command, 0, 12, allocator)
	p := strings.to_lower(strings.trim_space(pref), context.temp_allocator)
	for extra in CLOSE_SLASH_EXTRA {
		if len(p) == 0 || strings.has_prefix(extra, p) {
			help := "close target"
			switch extra {
			case "tab", "current", "this":
				help = "close current tab"
			case "view":
				help = "close file view pane"
			}
			append(&out, Slash_Command{
				name = extra,
				usage = fmt.tprintf("/close %s", extra),
				help = help,
			})
		}
	}
	for m in open_tab_name_matches(a, pref, context.temp_allocator) {
		append(&out, Slash_Command{
			name = m.name,
			usage = fmt.tprintf("/close %s", m.name),
			help = "close this tab",
		})
	}
	return out[:]
}

delete_slash_arg_matches :: proc(a: ^App, pref: string, allocator := context.temp_allocator) -> []Slash_Command {
	out := make([dynamic]Slash_Command, 0, 16, allocator)
	p := strings.to_lower(strings.trim_space(pref), context.temp_allocator)
	for extra in DELETE_SLASH_EXTRA {
		if len(p) == 0 || strings.has_prefix(extra, p) {
			help := "delete target"
			switch extra {
			case "current", "this", ".":
				help = "delete current session"
			case "tab":
				help = "delete open tab session"
			}
			append(&out, Slash_Command{
				name = extra,
				usage = fmt.tprintf("/delete %s", extra),
				help = help,
			})
		}
	}
	// Open tabs first, then disk sessions.
	for m in open_tab_name_matches(a, pref, context.temp_allocator) {
		append(&out, Slash_Command{
			name = m.name,
			usage = fmt.tprintf("/delete %s", m.name),
			help = "delete open session",
		})
	}
	for m in session_name_slash_arg_matches(pref, context.temp_allocator) {
		// Skip names already added from open tabs.
		dup := false
		for existing in out {
			if existing.name == m.name {
				dup = true
				break
			}
		}
		if dup {
			continue
		}
		append(&out, m)
	}
	return out[:]
}

session_name_slash_arg_matches :: proc(pref: string, allocator := context.temp_allocator) -> []Slash_Command {
	out := make([dynamic]Slash_Command, 0, 16, allocator)
	p := strings.to_lower(strings.trim_space(pref), context.temp_allocator)
	items := store.list_sessions(context.temp_allocator)
	for info in items {
		name_l := strings.to_lower(info.name, context.temp_allocator)
		if len(p) == 0 || strings.has_prefix(name_l, p) || strings.contains(name_l, p) {
			append(&out, Slash_Command{
				name = info.name,
				usage = info.name,
				help = "saved session",
			})
			if len(out) >= 16 {
				break
			}
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
	switch name {
	case "provider", "model", "tab", "close", "delete", "rm", "resume", "switch", "fork", "name", "rename":
		// Arg matches draw as a suggestion list instead of a one-line hint.
		return ""
	}
	cmd, ok := slash_find(name)
	if !ok {
		return ""
	}
	return fmt.tprintf("%s  %s", cmd.usage, cmd.help)
}

slash_complete :: proc(prefix: string, sel: int, a: ^App = nil) -> (completed: string, ok: bool) {
	matches := slash_matches(prefix, context.temp_allocator, a)
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
	if strings.has_prefix(p, "/") {
		body := p[1:]
		if sp := strings.index_byte(body, ' '); sp >= 0 {
			name := body[:sp]
			rest := strings.trim_left_space(body[sp + 1:])
			// Preserve a first subcommand token when completing the second.
			if fields := strings.fields(rest, context.temp_allocator); len(fields) >= 1 && strings.index_byte(rest, ' ') >= 0 {
				sub := fields[0]
				return fmt.tprintf("/%s %s %s", name, sub, cmd.name), true
			}
			switch name {
			case "provider", "model", "tab", "close", "delete", "rm", "resume", "switch", "fork", "name", "rename":
				return fmt.tprintf("/%s %s", name, cmd.name), true
			}
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
	for c in custom_command_matches("", context.temp_allocator) {
		fmt.sbprintf(&b, "  %-22s %s\n", c.usage, c.help)
	}
	strings.write_string(&b, "\nClick ? again or press Esc / F1 to close.")
	return strings.to_string(b)
}
