// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
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
	_ = session.session_compact_with_provider(a.session, p)
}

slash_cmd_rewind :: proc(a: ^App, args: string) {
	rest := strings.trim_space(args)
	n := 1
	if len(rest) > 0 {
		parsed, ok := strconv.parse_int(rest)
		if !ok || parsed <= 0 {
			session.session_set_status(a.session, "usage: /rewind [N]")
			return
		}
		n = parsed
	}
	p := provider.registry_active(&a.registry)
	_ = session.session_rewind(a.session, n, p)
}

slash_cmd_drop :: proc(a: ^App, args: string) {
	rest := strings.trim_space(args)
	if len(rest) == 0 {
		session.session_set_status(a.session, "usage: /drop N")
		return
	}
	n, ok := strconv.parse_int(rest)
	if !ok || n <= 0 {
		session.session_set_status(a.session, "usage: /drop N")
		return
	}
	_ = session.session_drop_pairs(a.session, n)
}

slash_cmd_sessions :: proc(a: ^App, args: string) {
	_ = args
	list := session.session_list_text()
	session.session_push_assistant(a.session, list)
	delete(list)
	session.session_set_status(a.session, "sessions")
}

slash_cmd_search :: proc(a: ^App, args: string) {
	q := strings.trim_space(args)
	if len(q) == 0 {
		session.session_set_status(a.session, "usage: /search query")
		return
	}
	list := session.session_search_text(q)
	session.session_push_assistant(a.session, list)
	delete(list)
	session.session_set_status(a.session, "search")
}

slash_cmd_resume :: proc(a: ^App, args: string) {
	name := strings.trim_space(args)
	if len(name) == 0 {
		session.session_set_status(a.session, "usage: /resume name")
		return
	}
	app_tab_open_named(a, name)
	app_refresh_credits(a)
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
		session.session_set_status(a.session, "usage: /name NAME [--force]")
		return
	}
	if len(name) == 0 {
		session.session_set_status(a.session, "usage: /name NAME [--force]")
		return
	}
	if session.session_rename(a.session, name, force) {
		subagent.runtime_set_session(&a.subagents, a.session.session_path, a.session.persist)
		provider.set_session(a.session.name)
	}
}

slash_cmd_new :: proc(a: ^App, args: string) {
	app_tab_new(a, strings.trim_space(args))
}

slash_cmd_tab :: proc(a: ^App, args: string) {
	rest := strings.trim_space(args)
	if len(rest) == 0 || rest == "list" {
		names := make([dynamic]string, context.temp_allocator)
		for t, i in a.tabs {
			mark := " "
			if i == a.active_tab {
				mark = "*"
			}
			append(
				&names,
				fmt.tprintf("%s%d:%s%s", mark, i + 1, t.sess.name, t.sess.busy ? " (busy)" : ""),
			)
		}
		session.session_set_status(
			a.session,
			fmt.tprintf("tabs: %s", strings.join(names[:], "  ", context.temp_allocator)),
		)
		return
	}
	switch rest {
	case "new":
		app_tab_new(a, "")
	case "next", "n":
		app_tab_cycle(a, 1)
	case "prev", "p":
		app_tab_cycle(a, -1)
	case "close", "w":
		app_tab_close(a, a.active_tab)
	case:
		if strings.has_prefix(rest, "new ") {
			app_tab_new(a, rest[len("new "):])
			return
		}
		if strings.has_prefix(rest, "open ") || strings.has_prefix(rest, "resume ") {
			idx := 5
			if strings.has_prefix(rest, "resume ") {
				idx = 7
			}
			app_tab_open_named(a, rest[idx:])
			return
		}
		if strings.has_prefix(rest, "close ") {
			target := strings.trim_space(rest[len("close "):])
			if idx, ok := app_tab_resolve(a, target); ok {
				app_tab_close(a, idx)
			} else {
				session.session_set_status(a.session, fmt.tprintf("no open tab matching %s", target))
			}
			return
		}
		if n, ok := strconv.parse_int(rest); ok {
			app_tab_goto(a, n - 1)
			return
		}
		// Bare name jumps to that open tab when unique.
		if idx, ok := app_tab_resolve(a, rest); ok {
			app_tab_goto(a, idx)
			return
		}
		session.session_set_status(
			a.session,
			"usage: /tab list|new [name]|open name|next|prev|close [name|N]|N",
		)
	}
}

// Resolve an open tab by 1-based index, exact name, or unique prefix.
app_tab_resolve :: proc(a: ^App, token: string) -> (idx: int, ok: bool) {
	tok := strings.trim_space(token)
	if len(tok) == 0 {
		return -1, false
	}
	if n, nok := strconv.parse_int(tok); nok {
		i := n - 1
		if i >= 0 && i < len(a.tabs) {
			return i, true
		}
		return -1, false
	}
	safe := store.sanitize_name(tok)
	// Exact match first.
	for t, i in a.tabs {
		if t.sess.name == safe || t.sess.name == tok {
			return i, true
		}
	}
	// Unique prefix (case-insensitive).
	low := strings.to_lower(safe, context.temp_allocator)
	found := -1
	count := 0
	for t, i in a.tabs {
		name_l := strings.to_lower(t.sess.name, context.temp_allocator)
		if strings.has_prefix(name_l, low) {
			count += 1
			found = i
		}
	}
	if count == 1 {
		return found, true
	}
	return -1, false
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
		session.session_set_status(a.session, "usage: /fork NAME [--force]")
		return
	}
	if session.session_fork(a.session, name, force) {
		subagent.runtime_set_session(&a.subagents, a.session.session_path, a.session.persist)
		provider.set_session(a.session.name)
	}
}

slash_cmd_delete :: proc(a: ^App, args: string) {
	rest := strings.trim_space(args)
	// Bare /delete (or "current" / ".") removes the active session after
	// closing its tab when needed.
	if len(rest) == 0 || rest == "." || rest == "current" || rest == "this" {
		app_delete_current_session(a)
		return
	}
	// /delete tab [name] closes (and optionally deletes) an open tab's
	// session files after the tab is gone.
	if rest == "tab" || strings.has_prefix(rest, "tab ") {
		target := ""
		if strings.has_prefix(rest, "tab ") {
			target = strings.trim_space(rest[len("tab "):])
		}
		app_delete_tab_session(a, target)
		return
	}
	safe := store.sanitize_name(rest)
	// If the session is open in a tab, close that tab first then delete.
	for t, i in a.tabs {
		if t.sess.name == safe {
			if t.sess.busy {
				session.session_set_status(a.session, "session is busy · /stop it first")
				return
			}
			// Last tab: switch to a fresh empty tab first so we can close it.
			if len(a.tabs) <= 1 {
				app_tab_new(a, "")
				// The old tab is now index 0 if new went after, find by name.
				for tt, j in a.tabs {
					if tt.sess.name == safe {
						app_tab_close(a, j)
						break
					}
				}
			} else {
				app_tab_close(a, i)
			}
			break
		}
	}
	// Re-check it is not still open (busy stop may have left it).
	for t in a.tabs {
		if t.sess.name == safe {
			session.session_set_status(a.session, "session still open · close the tab first")
			return
		}
	}
	ok, err := store.delete_session(safe)
	if !ok {
		session.session_set_status(a.session, err)
		return
	}
	session.session_set_status(a.session, fmt.tprintf("deleted %s", safe))
	app_tabs_persist(a)
}

// Close the current tab (when more than one is open) and delete its
// session files. With a single tab, create a fresh sibling first.
app_delete_current_session :: proc(a: ^App) {
	if a.session == nil {
		return
	}
	name := a.session.name
	if len(name) == 0 {
		session.session_set_status(a.session, "current session has no name on disk")
		return
	}
	if a.session.busy {
		session.session_set_status(a.session, "session is busy · /stop it first")
		return
	}
	safe := store.sanitize_name(name)
	// Ensure we will not land on a destroyed last tab.
	if len(a.tabs) <= 1 {
		app_tab_new(a, "")
	}
	// Close every open tab with this name (usually one).
	for {
		found := -1
		for t, i in a.tabs {
			if t.sess.name == safe {
				found = i
				break
			}
		}
		if found < 0 {
			break
		}
		before := len(a.tabs)
		app_tab_close(a, found)
		if len(a.tabs) >= before {
			// Close refused (busy join) and kept the tab.
			session.session_set_status(a.session, "could not close tab · try again")
			return
		}
	}
	ok, err := store.delete_session(safe)
	if !ok {
		session.session_set_status(a.session, err)
		return
	}
	session.session_set_status(a.session, fmt.tprintf("deleted %s", safe))
	app_tabs_persist(a)
}

app_delete_tab_session :: proc(a: ^App, target: string) {
	idx := a.active_tab
	if len(target) > 0 {
		ok: bool
		idx, ok = app_tab_resolve(a, target)
		if !ok {
			session.session_set_status(a.session, fmt.tprintf("no open tab matching %s", target))
			return
		}
	}
	if idx < 0 || idx >= len(a.tabs) {
		return
	}
	name := a.tabs[idx].sess.name
	if len(name) == 0 {
		session.session_set_status(a.session, "tab has no saved name")
		return
	}
	if a.tabs[idx].sess.busy {
		session.session_set_status(a.session, "session is busy · /stop it first")
		return
	}
	safe := store.sanitize_name(name)
	if len(a.tabs) <= 1 {
		app_tab_new(a, "")
		// Re-resolve after insert.
		idx, _ = app_tab_resolve(a, safe)
	}
	if idx >= 0 {
		app_tab_close(a, idx)
	}
	for t in a.tabs {
		if t.sess.name == safe {
			session.session_set_status(a.session, "tab still open")
			return
		}
	}
	ok, err := store.delete_session(safe)
	if !ok {
		session.session_set_status(a.session, err)
		return
	}
	session.session_set_status(a.session, fmt.tprintf("deleted %s", safe))
	app_tabs_persist(a)
}

slash_cmd_ephemeral :: proc(a: ^App, args: string) {
	rest := strings.trim_space(args)
	if rest == "off" {
		session.session_set_ephemeral(a.session, false)
		return
	}
	session.session_set_ephemeral(a.session, true)
}

slash_cmd_group :: proc(a: ^App, args: string) {
	name := strings.trim_space(args)
	if len(name) == 0 {
		g := a.session.group
		if len(g) == 0 {
			g = "(none)"
		}
		session.session_set_status(a.session, fmt.tprintf("group %s", g))
		return
	}
	session.session_set_group(a.session, name)
}

slash_cmd_undo :: proc(a: ^App, args: string) {
	_ = args
	msg, _ := tools.undo_last_write()
	session.session_set_status(a.session, msg)
	delete(msg)
}

slash_cmd_checkpoint :: proc(a: ^App, args: string) {
	trimmed := strings.trim_space(args)
	if len(trimmed) == 0 || trimmed == "list" {
		msg := tools.checkpoint_list()
		session.session_set_status(a.session, msg)
		delete(msg)
		return
	}
	fields := strings.fields(trimmed, context.temp_allocator)
	if len(fields) >= 2 && (fields[0] == "restore" || fields[0] == "diff") {
		id, ok := strconv.parse_int(fields[1])
		if !ok {
			session.session_set_status(a.session, "usage: /checkpoint restore N|diff N")
			return
		}
		if fields[0] == "restore" {
			msg, _ := tools.checkpoint_restore(id)
			session.session_set_status(a.session, msg)
			delete(msg)
			return
		}
		msg, _ := tools.checkpoint_diff(id)
		session.session_set_status(a.session, msg)
		delete(msg)
		return
	}
	session.session_set_status(a.session, "usage: /checkpoint [list|restore N|diff N]")
}

slash_cmd_reset :: proc(a: ^App, args: string) {
	rest := strings.to_lower(strings.trim_space(args), context.temp_allocator)
	if rest == "confirm" || rest == "yes" {
		if !a.reset_pending && rest == "yes" {
			session.session_set_status(a.session, "type /reset then /reset confirm")
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
		session.session_set_status(a.session, "reset cancelled")
		app_toast(a, "reset cancelled", .Info)
		return
	}
	a.reset_pending = true
	session.session_set_status(
		a.session,
		"DANGER: wipe sessions+env+keys · type /reset confirm",
	)
	app_toast_warn(a, "confirm with /reset confirm")
	app_mark_dirty(a)
}
