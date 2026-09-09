// SPDX-License-Identifier: 0BSD
/*
Slash commands: session lifecycle and history.
*/

package app

import "core:fmt"
import "core:strconv"
import "core:strings"
import "nullray:provider"
import "nullray:session"
import "nullray:store"
import "nullray:subagent"
import "nullray:tools"

slash_cmd_compact :: proc(a: ^App, args: string) {
	_ = args
	p := provider.registry_active(&a.registry)
	_ = session.session_compact_with_provider(&a.session, p)
}

slash_cmd_drop :: proc(a: ^App, args: string) {
	rest := strings.trim_space(args)
	if len(rest) == 0 {
		session.session_set_status(&a.session, "usage: /drop N")
		return
	}
	n, ok := strconv.parse_int(rest)
	if !ok || n <= 0 {
		session.session_set_status(&a.session, "usage: /drop N")
		return
	}
	_ = session.session_drop_pairs(&a.session, n)
}

slash_cmd_sessions :: proc(a: ^App, args: string) {
	_ = args
	list := session.session_list_text()
	session.session_push_assistant(&a.session, list)
	delete(list)
	session.session_set_status(&a.session, "sessions")
}

slash_cmd_search :: proc(a: ^App, args: string) {
	q := strings.trim_space(args)
	if len(q) == 0 {
		session.session_set_status(&a.session, "usage: /search query")
		return
	}
	list := session.session_search_text(q)
	session.session_push_assistant(&a.session, list)
	delete(list)
	session.session_set_status(&a.session, "search")
}

slash_cmd_resume :: proc(a: ^App, args: string) {
	name := strings.trim_space(args)
	if len(name) == 0 {
		session.session_set_status(&a.session, "usage: /resume name")
		return
	}
	if session.session_switch(&a.session, name) {
		_ = session.session_apply_saved_model(&a.session, &a.registry)
		subagent.runtime_set_session(&a.subagents, a.session.session_path, a.session.persist)
		provider.set_session(a.session.name)
		app_refresh_credits(a)
		session.session_set_status(&a.session, fmt.tprintf("resumed %s", a.session.name))
	} else {
		session.session_set_status(&a.session, fmt.tprintf("no session %s", name))
	}
}

slash_cmd_name :: proc(a: ^App, args: string) {
	rest := strings.trim_space(args)
	force := false
	name := rest
	if strings.has_suffix(rest, " --force") {
		force = true
		name = strings.trim_space(rest[:len(rest) - len(" --force")])
	} else if strings.has_prefix(rest, "--force ") {
		force = true
		name = strings.trim_space(rest[len("--force "):])
	} else if rest == "--force" {
		session.session_set_status(&a.session, "usage: /name NAME [--force]")
		return
	}
	if len(name) == 0 {
		session.session_set_status(&a.session, "usage: /name NAME [--force]")
		return
	}
	if session.session_rename(&a.session, name, force) {
		subagent.runtime_set_session(&a.subagents, a.session.session_path, a.session.persist)
		provider.set_session(a.session.name)
	}
}

slash_cmd_new :: proc(a: ^App, args: string) {
	name := strings.trim_space(args)
	if session.session_new(&a.session, name) {
		subagent.runtime_set_session(&a.subagents, a.session.session_path, a.session.persist)
		provider.set_session(a.session.name)
	}
}

slash_cmd_fork :: proc(a: ^App, args: string) {
	rest := strings.trim_space(args)
	force := false
	name := rest
	if strings.has_suffix(rest, " --force") {
		force = true
		name = strings.trim_space(rest[:len(rest) - len(" --force")])
	} else if strings.has_prefix(rest, "--force ") {
		force = true
		name = strings.trim_space(rest[len("--force "):])
	}
	if len(name) == 0 {
		session.session_set_status(&a.session, "usage: /fork NAME [--force]")
		return
	}
	if session.session_fork(&a.session, name, force) {
		subagent.runtime_set_session(&a.subagents, a.session.session_path, a.session.persist)
		provider.set_session(a.session.name)
	}
}

slash_cmd_delete :: proc(a: ^App, args: string) {
	name := strings.trim_space(args)
	if len(name) == 0 {
		session.session_set_status(&a.session, "usage: /delete name")
		return
	}
	safe := store.sanitize_name(name)
	if safe == a.session.name {
		session.session_set_status(&a.session, "switch or /new before deleting the open session")
		return
	}
	ok, err := store.delete_session(safe)
	if !ok {
		session.session_set_status(&a.session, err)
		return
	}
	session.session_set_status(&a.session, fmt.tprintf("deleted %s", safe))
}

slash_cmd_ephemeral :: proc(a: ^App, args: string) {
	rest := strings.trim_space(args)
	if rest == "off" {
		session.session_set_ephemeral(&a.session, false)
		return
	}
	session.session_set_ephemeral(&a.session, true)
}

slash_cmd_group :: proc(a: ^App, args: string) {
	name := strings.trim_space(args)
	if len(name) == 0 {
		g := a.session.group
		if len(g) == 0 {
			g = "(none)"
		}
		session.session_set_status(&a.session, fmt.tprintf("group %s", g))
		return
	}
	session.session_set_group(&a.session, name)
}

slash_cmd_undo :: proc(a: ^App, args: string) {
	_ = args
	msg, _ := tools.undo_last_write()
	session.session_set_status(&a.session, msg)
	delete(msg)
}

slash_cmd_checkpoint :: proc(a: ^App, args: string) {
	trimmed := strings.trim_space(args)
	if len(trimmed) == 0 || trimmed == "list" {
		msg := tools.checkpoint_list()
		session.session_set_status(&a.session, msg)
		delete(msg)
		return
	}
	fields := strings.fields(trimmed, context.temp_allocator)
	if len(fields) >= 2 && (fields[0] == "restore" || fields[0] == "diff") {
		id, ok := strconv.parse_int(fields[1])
		if !ok {
			session.session_set_status(&a.session, "usage: /checkpoint restore N|diff N")
			return
		}
		if fields[0] == "restore" {
			msg, _ := tools.checkpoint_restore(id)
			session.session_set_status(&a.session, msg)
			delete(msg)
			return
		}
		msg, _ := tools.checkpoint_diff(id)
		session.session_set_status(&a.session, msg)
		delete(msg)
		return
	}
	session.session_set_status(&a.session, "usage: /checkpoint [list|restore N|diff N]")
}

slash_cmd_reset :: proc(a: ^App, args: string) {
	rest := strings.to_lower(strings.trim_space(args), context.temp_allocator)
	if rest == "confirm" || rest == "yes" {
		if !a.reset_pending && rest == "yes" {
			session.session_set_status(&a.session, "type /reset then /reset confirm")
			return
		}
		ok := app_reset_all_state(a)
		if ok {
			app_toast_warn(a, "reset complete · setup next")
		} else {
			app_toast_error(a, "reset failed")
		}
		return
	}
	if rest == "cancel" || rest == "no" {
		a.reset_pending = false
		session.session_set_status(&a.session, "reset cancelled")
		app_toast(a, "reset cancelled", .Info)
		return
	}
	a.reset_pending = true
	session.session_set_status(
		&a.session,
		"DANGER: wipe sessions+env+keys · type /reset confirm",
	)
	app_toast_warn(a, "confirm with /reset confirm")
	app_mark_dirty(a)
}
