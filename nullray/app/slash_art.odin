// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
/art figlet|show|demo programmatic terminal art.
*/

package app

import "core:fmt"
import "core:strings"
import "nullray:art"
import "nullray:session"

slash_cmd_art :: proc(a: ^App, args: string) {
	rest := strings.trim_space(args)
	low := strings.to_lower(rest, context.temp_allocator)
	if len(rest) == 0 || low == "help" || low == "?" {
		session.session_push_assistant(
			a.session,
			`/art figlet TEXT
/art demo
/art show {json program}

Agent tool: show_art with ops figlet, rect, line, circle, bars, spark, plot, scatter, ansi.
Prefer show_art over freehand ASCII.`,
		)
		session.session_set_status(a.session, "art help")
		return
	}
	if strings.has_prefix(low, "figlet ") || strings.has_prefix(low, "banner ") {
		sp := strings.index_byte(rest, ' ')
		text := strings.trim_space(rest[sp+1:])
		if len(text) == 0 {
			session.session_set_status(a.session, "usage: /art figlet TEXT")
			return
		}
		body := art.art_figlet(text, true, context.allocator)
		_ = app_view_open_text(a, "figlet", body)
		delete(body)
		session.session_set_status(a.session, "art figlet")
		return
	}
	if low == "demo" {
		prog := `{
  "width": 56, "height": 18, "unicode": true,
  "ops": [
    {"op":"figlet","text":"NULL","x":1,"y":0,"color":"#5ad2ff"},
    {"op":"rect","x":0,"y":6,"w":56,"h":11,"color":"#556677"},
    {"op":"plot","fn":"sin","x":2,"y":7,"w":32,"h":9,"color":"#00ffcc"},
    {"op":"bars","x":36,"y":8,"h":8,"values":[2,5,3,8,6,4,7],"color":"#ffaa44"},
    {"op":"text","x":2,"y":16,"text":"plot=sin  bars=load","color":"#8899aa"}
  ]
}`
		plain, _, err := art.art_render_json(prog, context.allocator)
		if err != "" {
			session.session_set_status(a.session, err)
			delete(err)
			return
		}
		_ = app_view_open_text(a, "art demo", plain)
		delete(plain)
		session.session_set_status(a.session, "art demo")
		return
	}
	if strings.has_prefix(low, "show ") {
		js := strings.trim_space(rest[5:])
		plain, _, err := art.art_render_json(js, context.allocator)
		if err != "" {
			session.session_set_status(a.session, err)
			delete(err)
			return
		}
		_ = app_view_open_text(a, "art", plain)
		delete(plain)
		session.session_set_status(a.session, "art show")
		return
	}
	// bare text -> figlet
	if !strings.has_prefix(rest, "{") {
		body := art.art_figlet(rest, true, context.allocator)
		_ = app_view_open_text(a, "figlet", body)
		delete(body)
		session.session_set_status(a.session, "art figlet")
		return
	}
	plain, _, err := art.art_render_json(rest, context.allocator)
	if err != "" {
		session.session_set_status(a.session, err)
		delete(err)
		return
	}
	_ = app_view_open_text(a, "art", plain)
	delete(plain)
	session.session_set_status(a.session, "art")
}

app_art_show_cb :: proc(title, body: string, user: rawptr) {
	a := cast(^App)user
	if a == nil {
		return
	}
	_ = app_view_open_text(a, title, body)
}
