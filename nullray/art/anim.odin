// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Animation metadata for art programs (fps, loop, duration).
*/

package art

import "core:encoding/json"
import "core:strings"

Anim_Meta :: struct {
	fps:         int,
	loop:        bool,
	duration_ms: int,
	w, h:        int,
	unicode:     bool,
	animated:    bool,
}

art_parse_meta :: proc(raw: string) -> Anim_Meta {
	m := Anim_Meta{fps = 0, loop = true, duration_ms = 0, w = 60, h = 20, unicode = true}
	doc, perr := json.parse_string(raw, .JSON, allocator = context.temp_allocator)
	if perr != .None {
		return m
	}
	obj, ok := doc.(json.Object)
	if !ok {
		return m
	}
	m.w = json_int(obj, "width", 60)
	m.h = json_int(obj, "height", 20)
	m.fps = json_int(obj, "fps", 0)
	if m.fps <= 0 {
		m.fps = json_int(obj, "hz", 0)
	}
	m.duration_ms = json_int(obj, "duration_ms", json_int(obj, "ms", 0))
	m.loop = json_bool(obj, "loop", true)
	if json_bool(obj, "once", false) {
		m.loop = false
		if m.duration_ms <= 0 {
			m.duration_ms = 4000
		}
	}
	m.unicode = json_bool(obj, "unicode", true)
	if json_bool(obj, "ascii", false) {
		m.unicode = false
	}
	m.animated = m.fps > 0 || json_bool(obj, "animate", false) || art_ops_need_time(obj)
	if m.animated && m.fps <= 0 {
		m.fps = 12
	}
	if m.fps > 30 {
		m.fps = 30
	}
	if m.fps < 0 {
		m.fps = 0
	}
	return m
}

@(private)
art_ops_need_time :: proc(obj: json.Object) -> bool {
	ops_v, has := obj["ops"]
	if !has {
		return false
	}
	arr, ok := ops_v.(json.Array)
	if !ok {
		return false
	}
	for item in arr {
		op, ook := item.(json.Object)
		if !ook {
			continue
		}
		if json_bool(op, "animate", false) || json_bool(op, "pulse", false) ||
		   json_bool(op, "marquee", false) || json_bool(op, "orbit", false) ||
		   json_bool(op, "breathe", false) {
			return true
		}
		name, _ := json_str(op, "op")
		if len(name) == 0 {
			name, _ = json_str(op, "type")
		}
		n := strings.to_lower(name, context.temp_allocator)
		switch n {
		case "marquee", "bounce", "spinner", "pulse", "wave", "rain", "clock":
			return true
		}
		if n == "plot" || n == "fn" {
			if json_f64(op, "speed", 0) != 0 || json_f64(op, "phase", 0) != 0 {
				return true
			}
		}
	}
	return false
}

// Frame period helper.
art_frame_ms :: proc(meta: Anim_Meta) -> int {
	if meta.fps <= 0 {
		return 0
	}
	return max(1000 / meta.fps, 33)
}
