// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Live art scene player: ticks FPS, re-rasterizes program into the side pane.
*/

package app

import "core:fmt"
import "core:strings"
import "core:time"
import "nullray:art"
import "nullray:session"

app_art_scene_stop :: proc(a: ^App) {
	a.art_scene_on = false
	delete(a.art_scene_json)
	a.art_scene_json = {}
	delete(a.art_scene_title)
	a.art_scene_title = {}
	a.art_scene_fps = 0
}

app_art_scene_start :: proc(a: ^App, title, schema: string) {
	meta := art.art_parse_meta(schema)
	delete(a.art_scene_json)
	a.art_scene_json = strings.clone(schema)
	delete(a.art_scene_title)
	a.art_scene_title = strings.clone(len(title) > 0 ? title : "art")
	a.art_scene_start = time.tick_now()
	a.art_scene_last = a.art_scene_start
	a.art_scene_fps = meta.fps
	a.art_scene_loop = meta.loop
	a.art_scene_dur_ms = meta.duration_ms
	a.art_scene_on = meta.animated && meta.fps > 0
	app_art_scene_paint(a, 0)
	if a.art_scene_on {
		session.session_set_status(
			a.session,
			fmt.tprintf("art anim %s %dfps · Esc closes pane", a.art_scene_title, a.art_scene_fps),
		)
	} else {
		session.session_set_status(a.session, fmt.tprintf("art %s", a.art_scene_title))
	}
	app_mark_dirty(a)
}

app_art_scene_paint :: proc(a: ^App, t_sec: f64) {
	if len(a.art_scene_json) == 0 {
		return
	}
	plain, _, err := art.art_render_json_ex(a.art_scene_json, t_sec, context.allocator)
	if err != "" {
		delete(err)
		delete(plain)
		return
	}
	title := a.art_scene_title
	if a.art_scene_on {
		title = fmt.tprintf("%s · live", a.art_scene_title)
	}
	_ = app_view_open_text(a, title, plain)
	delete(plain)
}

app_art_scene_tick :: proc(a: ^App) -> bool {
	if !a.art_scene_on || len(a.art_scene_json) == 0 {
		return false
	}
	if !a.view_open {
		app_art_scene_stop(a)
		return false
	}
	now := time.tick_now()
	elapsed_ms := int(time.tick_diff(a.art_scene_start, now) / time.Millisecond)
	if a.art_scene_dur_ms > 0 && elapsed_ms >= a.art_scene_dur_ms {
		if a.art_scene_loop {
			a.art_scene_start = now
			elapsed_ms = 0
		} else {
			t := f64(a.art_scene_dur_ms) / 1000.0
			app_art_scene_paint(a, t)
			a.art_scene_on = false
			session.session_set_status(a.session, "art anim done")
			return true
		}
	}
	frame_ms := art.art_frame_ms(art.Anim_Meta{fps = a.art_scene_fps})
	if frame_ms <= 0 {
		frame_ms = 80
	}
	since_last := int(time.tick_diff(a.art_scene_last, now) / time.Millisecond)
	if since_last < frame_ms {
		return false
	}
	a.art_scene_last = now
	t_sec := f64(elapsed_ms) / 1000.0
	app_art_scene_paint(a, t_sec)
	return true
}
