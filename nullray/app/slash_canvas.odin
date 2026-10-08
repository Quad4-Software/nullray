// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
/canvas list|open|save|rm and /learn skill persistence.
*/

package app

import "core:fmt"
import "core:os"
import "core:strings"
import "nullray:ask"
import "nullray:session"
import "nullray:skills"
import "nullray:store"

slash_cmd_canvas :: proc(a: ^App, args: string) {
	rest := strings.trim_space(args)
	low := strings.to_lower(rest, context.temp_allocator)
	if len(rest) == 0 || low == "list" || low == "ls" {
		txt := store.canvas_list_text(context.allocator)
		session.session_push_assistant(a.session, txt)
		delete(txt)
		session.session_set_status(a.session, "canvas list")
		app_mark_dirty(a)
		return
	}
	if strings.has_prefix(low, "open ") || low == "open" {
		id := ""
		if strings.has_prefix(low, "open ") {
			id = strings.trim_space(rest[5:])
		}
		if len(id) == 0 {
			session.session_set_status(a.session, "usage: /canvas open ID")
			return
		}
		app_canvas_open(a, id)
		return
	}
	if strings.has_prefix(low, "rm ") || strings.has_prefix(low, "delete ") || strings.has_prefix(low, "remove ") {
		id := strings.trim_space(rest[strings.index(rest, " ") + 1:])
		if store.canvas_delete(id) {
			session.session_set_status(a.session, fmt.tprintf("canvas deleted %s", id))
		} else {
			session.session_set_status(a.session, fmt.tprintf("canvas not found %s", id))
		}
		return
	}
	if strings.has_prefix(low, "save") {
		id := ""
		if strings.has_prefix(low, "save ") {
			id = strings.trim_space(rest[5:])
		}
		app_canvas_save_current(a, id)
		return
	}
	session.session_set_status(a.session, "usage: /canvas list|open ID|save [ID]|rm ID")
}

app_canvas_open :: proc(a: ^App, id: string) {
	schema, title, err := store.canvas_load(id, context.allocator)
	if err != "" {
		session.session_set_status(a.session, fmt.tprintf("canvas: %s", err))
		delete(err)
		return
	}
	defer delete(schema)
	defer delete(title)
	def, perr := ask.view_parse(schema, context.allocator)
	if perr != "" {
		session.session_set_status(a.session, fmt.tprintf("canvas corrupt: %s", perr))
		delete(perr)
		return
	}
	// Swap in form without a live ask waiter: open as canvas pane + optional modal.
	app_ask_clear_full(a)
	a.view_form = def
	a.view_form_active = true
	a.ask_active = true
	a.ask_kind = .View
	a.ask_id = 1
	a.ask_prompt = strings.clone(title)
	a.view_form_focus = 0
	delete(a.view_canvas_id)
	a.view_canvas_id = strings.clone(id)
	delete(a.view_canvas_schema)
	a.view_canvas_schema = strings.clone(schema)
	if a.view_form.placement == .Panel || a.view_form.placement == .Modal {
		app_view_form_seed_canvas(a)
	}
	session.session_set_status(a.session, fmt.tprintf("canvas open %s", id))
	app_mark_dirty(a)
}

app_canvas_save_current :: proc(a: ^App, id_hint: string) {
	schema := a.view_canvas_schema
	title := a.view_form.title
	if len(schema) == 0 && a.view_form_active {
		// Rebuild a minimal schema from live form is not available. Require prior schema.
		session.session_set_status(a.session, "no canvas schema to save (open a panel show_view first)")
		return
	}
	if len(schema) == 0 {
		session.session_set_status(a.session, "nothing to save")
		return
	}
	hint := id_hint
	if len(hint) == 0 {
		hint = a.view_canvas_id
	}
	if len(hint) == 0 {
		hint = title
	}
	sid, err := store.canvas_save(hint, title, schema, context.allocator)
	if err != "" {
		session.session_set_status(a.session, fmt.tprintf("save failed: %s", err))
		delete(err)
		return
	}
	delete(a.view_canvas_id)
	a.view_canvas_id = sid
	session.session_set_status(a.session, fmt.tprintf("canvas saved %s", sid))
}

/*
/learn [id]: write a compact skill from recent assistant turns or explicit body.
Usage:
  /learn my-skill
  /learn my-skill short description here
*/
slash_cmd_learn :: proc(a: ^App, args: string) {
	rest := strings.trim_space(args)
	if len(rest) == 0 {
		session.session_set_status(a.session, "usage: /learn ID [description]")
		return
	}
	id := rest
	desc := ""
	if sp := strings.index_byte(rest, ' '); sp > 0 {
		id = strings.trim_space(rest[:sp])
		desc = strings.trim_space(rest[sp+1:])
	}
	// Body: last assistant message, truncated for token efficiency.
	body := ""
	for i := len(a.session.messages) - 1; i >= 0; i -= 1 {
		if a.session.messages[i].role == .Assistant {
			body = a.session.messages[i].content
			break
		}
	}
	if len(strings.trim_space(body)) == 0 {
		session.session_set_status(a.session, "no assistant text to learn from")
		return
	}
	// Cap skill body so later load_skill stays cheap.
	max_body := 4000
	if len(body) > max_body {
		body = body[:max_body]
	}
	if len(desc) == 0 {
		desc = fmt.tprintf("Learned skill %s", id)
	}
	path, err := skills.skills_save(id, id, desc, body, nil, context.allocator)
	if err != "" {
		session.session_set_status(a.session, fmt.tprintf("learn failed: %s", err))
		delete(err)
		return
	}
	msg := fmt.tprintf("skill learned id=%s path=%s (use load_skill)", id, path)
	session.session_push_assistant(a.session, msg)
	delete(msg)
	delete(path)
	session.session_set_status(a.session, "learn done")
	app_mark_dirty(a)
}
