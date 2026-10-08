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
/art demo   (animated)
/art anim
/art stop
/art show {json program with optional fps}

Agent tool show_art: figlet, marquee, bounce, spinner, wave, plot+speed, bars animate, orbit lines.
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
	if low == "demo" || low == "anim" || low == "demo anim" {
		prog := `{
  "width": 56, "height": 18, "unicode": true, "fps": 14, "loop": true,
  "ops": [
    {"op":"figlet","text":"LIVE","x":1,"y":0,"color":"#5ad2ff","pulse":true,"speed":3},
    {"op":"spinner","x":52,"y":1,"color":"#ffaa44"},
    {"op":"marquee","text":"nullray art engine · no freehand ascii · ","y":5,"speed":16,"color":"#88aacc"},
    {"op":"rect","x":0,"y":6,"w":56,"h":11,"color":"#445566"},
    {"op":"plot","fn":"sin","x":2,"y":7,"w":32,"h":9,"speed":2.5,"color":"#00ffcc"},
    {"op":"bars","x":36,"y":8,"h":8,"values":[2,5,3,8,6,4,7,3,5],"animate":true,"speed":3,"color":"#ffaa44"},
    {"op":"bounce","x":1,"y":16,"w":54,"text":">>","speed":22,"color":"#ff6688"},
    {"op":"clock","x":44,"y":16,"color":"#8899aa"}
  ]
}`
		app_art_scene_start(a, "art demo", prog)
		return
	}
	if low == "stop" {
		app_art_scene_stop(a)
		session.session_set_status(a.session, "art stop")
		return
	}
	if strings.has_prefix(low, "show ") {
		js := strings.trim_space(rest[5:])
		app_art_scene_start(a, "art", js)
		return
	}
	// bare text -> figlet
	if !strings.has_prefix(rest, "{") {
		body := art.art_figlet(rest, true, context.allocator)
		app_art_scene_stop(a)
		_ = app_view_open_text(a, "figlet", body)
		delete(body)
		session.session_set_status(a.session, "art figlet")
		return
	}
	app_art_scene_start(a, "art", rest)
}

// Tool callback: title + schema (or still body).
app_art_show_cb :: proc(title, body: string, user: rawptr) {
	a := cast(^App)user
	if a == nil {
		return
	}
	// If body looks like a program, play it (animates when fps/ops need time).
	trim := strings.trim_space(body)
	if strings.has_prefix(trim, "{") && (strings.contains(trim, `"ops"`) || strings.contains(trim, `"figlet"`) || strings.contains(trim, `"fps"`)) {
		app_art_scene_start(a, title, trim)
		return
	}
	app_art_scene_stop(a)
	_ = app_view_open_text(a, title, body)
}
