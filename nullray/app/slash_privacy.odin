// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Slash commands: /scrub, /encrypt, /demo (malleable UI smoke).
*/

package app

import "core:fmt"
import "core:os"
import "core:strings"
import "nullray:ask"
import "nullray:constants"
import "nullray:session"
import "nullray:store"
import "nullray:ui"

slash_cmd_scrub :: proc(a: ^App, args: string) {
	rest := strings.trim_space(args)
	low := strings.to_lower(rest, context.temp_allocator)
	if len(rest) == 0 || low == "all" || low == "session" {
		n := session.session_scrub_all(a.session)
		session.session_set_status(a.session, fmt.tprintf("scrubbed %d messages", n))
		app_mark_dirty(a)
		return
	}
	if low == "last" {
		n := session.session_forget_last_user(a.session)
		session.session_set_status(a.session, fmt.tprintf("forgot last turn (%d msgs)", n))
		app_mark_dirty(a)
		return
	}
	if strings.has_prefix(low, "matching ") || strings.has_prefix(low, "match ") {
		q := strings.trim_space(rest[strings.index(rest, " ") + 1:])
		n := session.session_forget_matching(a.session, q)
		session.session_set_status(a.session, fmt.tprintf("forgot %d matching %q", n, q))
		app_mark_dirty(a)
		return
	}
	// bare needle
	n := session.session_forget_matching(a.session, rest)
	session.session_set_status(a.session, fmt.tprintf("forgot %d matching %q", n, rest))
	app_mark_dirty(a)
}

slash_cmd_encrypt :: proc(a: ^App, args: string) {
	rest := strings.trim_space(args)
	low := strings.to_lower(rest, context.temp_allocator)
	if len(rest) == 0 || low == "status" {
		on := store.session_crypto_has_passphrase() || len(store.session_crypto_passphrase()) > 0
		session.session_set_status(
			a.session,
			fmt.tprintf("session encrypt %s · /encrypt on KEY | off | status", on ? "on" : "off"),
		)
		return
	}
	if low == "off" || low == "clear" || low == "disable" {
		store.session_crypto_clear_passphrase()
		os.unset_env(constants.ENV_SESSION_KEY)
		session.session_set_status(a.session, "session encrypt off (new saves plain)")
		return
	}
	key := rest
	if strings.has_prefix(low, "on ") {
		key = strings.trim_space(rest[3:])
	} else if low == "on" {
		session.session_set_status(a.session, "usage: /encrypt on PASSPHRASE")
		return
	}
	if len(key) < 8 {
		session.session_set_status(a.session, "passphrase too short (min 8)")
		return
	}
	store.session_crypto_set_passphrase(key)
	os.set_env(constants.ENV_SESSION_KEY, key)
	session.session_maybe_persist(a.session)
	session.session_set_status(a.session, "session encrypt on (transcript sealed)")
	app_mark_dirty(a)
}

slash_cmd_demo :: proc(a: ^App, args: string) {
	rest := strings.trim_space(args)
	low := strings.to_lower(rest, context.temp_allocator)
	if low == "malleable" || low == "ui" || low == "tui" || len(rest) == 0 {
		app_demo_malleable(a)
		return
	}
	session.session_set_status(a.session, "usage: /demo malleable")
}

app_demo_malleable :: proc(a: ^App) {
	// Push a guided smoke of the malleable surface into the transcript and
	// open a sample form so the human can submit without writing a prompt.
	guide := strings.clone(
		`Malleable UI demo
1. show_view form opens below (name + optional password vault field).
2. Submit to prove password values return [redacted].
3. Try: /tui get   /encrypt status   /scrub last
4. Agent tip: call show_view / set_tui from tools (visible on local Tiny).`,
	)
	session.session_push_assistant(a.session, guide)
	delete(guide)

	schema := `{
  "title": "Demo form",
  "placement": "modal",
  "width": 62,
  "height": 16,
  "accent": "cyan",
  "body": "Name is normal. Secret is vaulted.",
  "fields": [
    {"id": "name", "type": "text", "label": "Name", "default": "dev", "required": true},
    {"id": "token", "type": "password", "label": "Secret", "persist": "vault"},
    {"id": "note", "type": "text", "label": "Private note", "persist": "omit", "default": "never sent"}
  ],
  "actions": [
    {"id": "submit", "type": "submit", "label": "OK", "primary": true},
    {"id": "cancel", "type": "cancel", "label": "Cancel"}
  ]
}`
	// Drive ask channel as if the tool requested it, so TUI path is identical.
	ask.set_ui_enabled(true)
	go_req := true
	_ = go_req
	// Non-blocking seed of form: parse into app state if not busy.
	if !a.view_form_active && !a.ask_active {
		def, perr := ask.view_parse(schema, context.allocator)
		if perr == "" {
			app_ask_clear_full(a)
			a.view_form = def
			a.view_form_active = true
			a.ask_active = true
			a.ask_kind = .View
			a.ask_prompt = strings.clone("Demo form")
			a.view_form_focus = 0
			// Fake id so Esc cancel works without hanging a real waiter.
			a.ask_id = 1
			if a.view_form.placement == .Panel {
				_ = app_view_open_text(a, "Demo form", a.view_form.body)
			}
			session.session_set_status(a.session, "demo: submit the form (password vaults)")
		} else {
			delete(perr)
			session.session_set_status(a.session, "demo parse failed")
		}
	} else {
		session.session_set_status(a.session, "demo: clear active ask first")
	}
	app_mark_dirty(a)
}
