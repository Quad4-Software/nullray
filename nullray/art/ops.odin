// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
JSON art program compiler.

Static and timed ops. t_sec is seconds since scene start (0 for stills).

{
  "width": 56, "height": 16, "fps": 12, "loop": true,
  "ops": [
    {"op":"figlet","text":"SHIP","x":2,"y":0,"color":"#00ffcc"},
    {"op":"marquee","text":"deploying...","y":6,"speed":12,"color":"cyan"},
    {"op":"plot","fn":"sin","x":2,"y":7,"w":40,"h":8,"speed":2},
    {"op":"spinner","x":50,"y":2},
    {"op":"bounce","x":0,"y":14,"w":56,"text":"o","speed":20}
  ]
}
*/

package art

import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:strconv"
import "core:strings"
import "nullray:ui"

art_render_json :: proc(
	raw: string,
	allocator := context.allocator,
) -> (plain: string, ansi_out: string, err: string) {
	return art_render_json_ex(raw, 0, allocator)
}

art_render_json_ex :: proc(
	raw: string,
	t_sec: f64,
	allocator := context.allocator,
) -> (plain: string, ansi_out: string, err: string) {
	doc, perr := json.parse_string(raw, .JSON, allocator = context.temp_allocator)
	if perr != .None {
		return "", "", strings.clone("art json invalid", allocator)
	}
	obj, ok := doc.(json.Object)
	if !ok {
		return "", "", strings.clone("art root must be object", allocator)
	}
	w := json_int(obj, "width", 60)
	h := json_int(obj, "height", 20)
	uni := json_bool(obj, "unicode", true)
	if json_bool(obj, "ascii", false) {
		uni = false
	}
	c := canvas_create(w, h, uni, '#', context.temp_allocator)
	t := t_sec
	if t < 0 {
		t = 0
	}

	if txt, tok := json_str(obj, "figlet"); tok && len(txt) > 0 {
		fg0, hf0 := json_color(obj, "color")
		_ = canvas_figlet(&c, txt, json_int(obj, "x", 0), json_int(obj, "y", 0), fg0, hf0)
	}
	if txt, tok := json_str(obj, "text"); tok && len(txt) > 0 && !json_has(obj, "ops") {
		fg0, hf0 := json_color(obj, "color")
		canvas_text(&c, json_int(obj, "x", 0), json_int(obj, "y", 0), txt, fg0, hf0)
	}

	if ops_v, has := obj["ops"]; has {
		arr, aok := ops_v.(json.Array)
		if !aok {
			return "", "", strings.clone("ops must be array", allocator)
		}
		if len(arr) > 200 {
			return "", "", strings.clone("too many ops (max 200)", allocator)
		}
		for item in arr {
			op_obj, ook := item.(json.Object)
			if !ook {
				continue
			}
			apply_op(&c, op_obj, t)
		}
	}

	plain = canvas_to_string(&c, allocator)
	ansi_out = canvas_to_ansi(&c, allocator)
	// All-space frames are valid (e.g. marquee fully off-screen for a tick).
	return plain, ansi_out, ""
}

art_figlet :: proc(text: string, unicode := true, allocator := context.allocator) -> string {
	return figlet_string(text, unicode, allocator)
}

@(private)
apply_op :: proc(c: ^Canvas, op_obj: json.Object, t: f64) {
	op_name, _ := json_str(op_obj, "op")
	if len(op_name) == 0 {
		op_name, _ = json_str(op_obj, "type")
	}
	op_name = strings.to_lower(op_name, context.temp_allocator)
	fg, has_fg := json_color(op_obj, "color")
	if !has_fg {
		fg, has_fg = json_color(op_obj, "fg")
	}
	// pulse color brightness if animate
	if has_fg && json_bool(op_obj, "pulse", false) {
		speed := json_f64(op_obj, "speed", 2)
		ph := 0.5 + 0.5 * math.sin(t * speed)
		fg = ui.Color{
			u8(clamp(int(f64(fg.r) * (0.45 + 0.55 * ph)), 0, 255)),
			u8(clamp(int(f64(fg.g) * (0.45 + 0.55 * ph)), 0, 255)),
			u8(clamp(int(f64(fg.b) * (0.45 + 0.55 * ph)), 0, 255)),
		}
	}

	switch op_name {
	case "clear":
		canvas_clear(c)
	case "figlet", "banner":
		txt, _ := json_str(op_obj, "text")
		if len(txt) == 0 {
			txt, _ = json_str(op_obj, "s")
		}
		x := json_int(op_obj, "x", 0)
		y := json_int(op_obj, "y", 0)
		if json_bool(op_obj, "marquee", false) || strings.to_lower(json_str_def(op_obj, "motion", ""), context.temp_allocator) == "marquee" {
			speed := json_f64(op_obj, "speed", 10)
			tw := fig_width(txt)
			span := max(c.w + tw, 1)
			x = int(-math.mod(t * speed, f64(span))) + c.w
		}
		_ = canvas_figlet(c, txt, x, y, fg, has_fg)
	case "text", "label":
		txt, _ := json_str(op_obj, "text")
		if len(txt) == 0 {
			txt, _ = json_str(op_obj, "s")
		}
		canvas_text(c, json_int(op_obj, "x", 0), json_int(op_obj, "y", 0), txt, fg, has_fg)
	case "marquee":
		txt, _ := json_str(op_obj, "text")
		if len(txt) == 0 {
			txt, _ = json_str(op_obj, "s")
		}
		y := json_int(op_obj, "y", 0)
		speed := json_f64(op_obj, "speed", 14)
		// measure display width roughly
		tw := 0
		for r in txt {
			tw += max(1, ui.rune_cols(r))
		}
		span := max(c.w + tw, 1)
		x := c.w - int(math.mod(t * speed, f64(span)))
		if json_bool(op_obj, "reverse", false) {
			x = int(math.mod(t * speed, f64(span))) - tw
		}
		canvas_text(c, x, y, txt, fg, has_fg)
	case "bounce":
		txt, _ := json_str(op_obj, "text")
		if len(txt) == 0 {
			txt = "o"
		}
		y := json_int(op_obj, "y", c.h / 2)
		x0 := json_int(op_obj, "x", 0)
		ww := json_int(op_obj, "w", c.w)
		if ww < 2 {
			ww = c.w
		}
		tw := 0
		for r in txt {
			tw += max(1, ui.rune_cols(r))
		}
		path := max(ww - tw, 1)
		speed := json_f64(op_obj, "speed", 16)
		cycle := f64(path) * 2
		pos := math.mod(t * speed, cycle)
		x: int
		if pos <= f64(path) {
			x = x0 + int(pos)
		} else {
			x = x0 + path - int(pos - f64(path))
		}
		canvas_text(c, x, y, txt, fg, has_fg)
	case "spinner":
		x := json_int(op_obj, "x", 0)
		y := json_int(op_obj, "y", 0)
		frames := "|/-\\"
		if c.unicode {
			frames = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
		}
		speed := json_f64(op_obj, "speed", 10)
		// rune index
		n := 0
		for _ in frames {
			n += 1
		}
		if n <= 0 {
			n = 1
		}
		idx := int(math.mod(t * speed, f64(n)))
		if idx < 0 {
			idx = 0
		}
		i := 0
		ch: rune = '|'
		for r in frames {
			if i == idx {
				ch = r
				break
			}
			i += 1
		}
		canvas_put(c, x, y, ch, fg, has_fg)
	case "wave", "rain":
		// fill a row strip with a travelling sine ink pattern
		x := json_int(op_obj, "x", 0)
		y := json_int(op_obj, "y", 0)
		ww := json_int(op_obj, "w", c.w)
		hh := json_int(op_obj, "h", 1)
		speed := json_f64(op_obj, "speed", 4)
		ink := canvas_ink(c)
		for dy in 0 ..< hh {
			for dx in 0 ..< ww {
				phase := f64(dx) * 0.35 + f64(dy) * 0.5 - t * speed
				v := math.sin(phase)
				if op_name == "rain" {
					// sparse drops
					h := math.sin(f64(dx) * 1.7 + f64(dy) * 3.1 + t * speed)
					if h > 0.75 {
						canvas_put(c, x + dx, y + dy, c.unicode ? '·' : '.', fg, has_fg)
					}
				} else if v > 0.2 {
					canvas_put(c, x + dx, y + dy, ink, fg, has_fg)
				}
			}
		}
	case "clock":
		x := json_int(op_obj, "x", 0)
		y := json_int(op_obj, "y", 0)
		secs := int(t) % 86400
		hh := secs / 3600
		mm := (secs / 60) % 60
		ss := secs % 60
		label := fmt.tprintf("%02d:%02d:%02d", hh, mm, ss)
		canvas_text(c, x, y, label, fg, has_fg)
	case "rect", "box":
		canvas_rect(
			c,
			json_int(op_obj, "x", 0),
			json_int(op_obj, "y", 0),
			json_int(op_obj, "w", json_int(op_obj, "width", 10)),
			json_int(op_obj, "h", json_int(op_obj, "height", 5)),
			json_bool(op_obj, "fill", false),
			fg,
			has_fg,
		)
	case "hline":
		canvas_hline(c, json_int(op_obj, "x", 0), json_int(op_obj, "y", 0), json_int(op_obj, "w", 10), 0, fg, has_fg)
	case "vline":
		canvas_vline(c, json_int(op_obj, "x", 0), json_int(op_obj, "y", 0), json_int(op_obj, "h", 5), 0, fg, has_fg)
	case "line":
		x1 := json_int(op_obj, "x1", json_int(op_obj, "x", 0))
		y1 := json_int(op_obj, "y1", json_int(op_obj, "y", 0))
		x2 := json_int(op_obj, "x2", 10)
		y2 := json_int(op_obj, "y2", 10)
		// optional orbit endpoint around center
		if json_bool(op_obj, "orbit", false) {
			cx := json_int(op_obj, "cx", (x1 + x2) / 2)
			cy := json_int(op_obj, "cy", (y1 + y2) / 2)
			r := json_int(op_obj, "r", 5)
			speed := json_f64(op_obj, "speed", 2)
			ang := t * speed
			x2 = cx + int(math.cos(ang) * f64(r) * 2) // *2 for cell aspect
			y2 = cy + int(math.sin(ang) * f64(r))
		}
		canvas_line(c, x1, y1, x2, y2, 0, fg, has_fg)
	case "circle":
		cx := json_int(op_obj, "cx", json_int(op_obj, "x", 0))
		cy := json_int(op_obj, "cy", json_int(op_obj, "y", 0))
		r := json_int(op_obj, "r", json_int(op_obj, "radius", 3))
		if json_bool(op_obj, "breathe", false) {
			speed := json_f64(op_obj, "speed", 2)
			r = max(1, r + int(math.sin(t * speed) * f64(max(r / 2, 1))))
		}
		canvas_circle(c, cx, cy, r, json_bool(op_obj, "fill", false), fg, has_fg)
	case "bars", "bar":
		vals := json_f64s(op_obj, "values")
		if json_bool(op_obj, "animate", false) && len(vals) > 0 {
			// scroll phase through series
			speed := json_f64(op_obj, "speed", 4)
			shift := int(t * speed) % len(vals)
			shifted := make([]f64, len(vals), context.temp_allocator)
			for i in 0 ..< len(vals) {
				shifted[i] = vals[(i + shift) % len(vals)]
			}
			// also breathe amplitudes
			for i in 0 ..< len(shifted) {
				shifted[i] *= 0.6 + 0.4 * (0.5 + 0.5 * math.sin(t * 2 + f64(i) * 0.4))
			}
			vals = shifted
		}
		canvas_bars(c, json_int(op_obj, "x", 0), json_int(op_obj, "y", 0), json_int(op_obj, "h", json_int(op_obj, "height", 8)), vals, fg, has_fg)
	case "spark", "sparkline":
		vals := json_f64s(op_obj, "values")
		if json_bool(op_obj, "animate", false) && len(vals) > 0 {
			speed := json_f64(op_obj, "speed", 6)
			shift := int(t * speed) % len(vals)
			shifted := make([]f64, len(vals), context.temp_allocator)
			for i in 0 ..< len(vals) {
				shifted[i] = vals[(i + shift) % len(vals)]
			}
			vals = shifted
		}
		canvas_spark(c, json_int(op_obj, "x", 0), json_int(op_obj, "y", 0), vals, fg, has_fg)
	case "plot", "fn":
		fn, _ := json_str(op_obj, "fn")
		if len(fn) == 0 {
			fn, _ = json_str(op_obj, "f")
		}
		if len(fn) == 0 {
			fn = "sin"
		}
		speed := json_f64(op_obj, "speed", 0)
		phase := json_f64(op_obj, "phase", 0) + t * speed
		canvas_plot_fn_phase(
			c,
			json_int(op_obj, "x", 0),
			json_int(op_obj, "y", 0),
			json_int(op_obj, "w", 40),
			json_int(op_obj, "h", 10),
			fn,
			json_int(op_obj, "samples", 0),
			phase,
			fg,
			has_fg,
		)
	case "scatter", "xy":
		xs := json_f64s(op_obj, "xs")
		if len(xs) == 0 {
			xs = json_f64s(op_obj, "x")
		}
		ys := json_f64s(op_obj, "ys")
		if len(ys) == 0 {
			ys = json_f64s(op_obj, "y")
		}
		if len(xs) == 0 || len(ys) == 0 {
			if pv, ph := op_obj["points"]; ph {
				if parr, pok := pv.(json.Array); pok {
					xs = make([]f64, len(parr), context.temp_allocator)
					ys = make([]f64, len(parr), context.temp_allocator)
					for p, pi in parr {
						if pair, pair_ok := p.(json.Array); pair_ok && len(pair) >= 2 {
							xs[pi] = json_num_val(pair[0])
							ys[pi] = json_num_val(pair[1])
						}
					}
				}
			}
		}
		canvas_plot_xy(
			c,
			json_int(op_obj, "ox", json_int(op_obj, "left", 0)),
			json_int(op_obj, "oy", json_int(op_obj, "top", 0)),
			json_int(op_obj, "w", 40),
			json_int(op_obj, "h", 12),
			xs,
			ys,
			fg,
			has_fg,
		)
	case "ansi", "ans":
		txt, _ := json_str(op_obj, "text")
		if len(txt) == 0 {
			txt, _ = json_str(op_obj, "data")
		}
		txt, _ = strings.replace_all(txt, "\\n", "\n", context.temp_allocator)
		txt, _ = strings.replace_all(txt, "\\e", "\x1b", context.temp_allocator)
		txt, _ = strings.replace_all(txt, "\\x1b", "\x1b", context.temp_allocator)
		txt, _ = strings.replace_all(txt, "\\u001b", "\x1b", context.temp_allocator)
		_ = ansi_blit(c, txt, json_int(op_obj, "x", 0), json_int(op_obj, "y", 0))
	case "put", "pixel":
		ch_s, _ := json_str(op_obj, "ch")
		r: rune = '#'
		if len(ch_s) > 0 {
			r = rune(ch_s[0])
		}
		canvas_put(c, json_int(op_obj, "x", 0), json_int(op_obj, "y", 0), r, fg, has_fg)
	}
}

@(private)
json_has :: proc(obj: json.Object, key: string) -> bool {
	_, ok := obj[key]
	return ok
}

@(private)
json_str :: proc(obj: json.Object, key: string) -> (string, bool) {
	v, ok := obj[key]
	if !ok {
		return "", false
	}
	if s, sok := v.(json.String); sok {
		return string(s), true
	}
	return "", false
}

@(private)
json_str_def :: proc(obj: json.Object, key, def: string) -> string {
	s, ok := json_str(obj, key)
	if ok {
		return s
	}
	return def
}

@(private)
json_int :: proc(obj: json.Object, key: string, def: int) -> int {
	v, ok := obj[key]
	if !ok {
		return def
	}
	return int(json_num_val(v, f64(def)))
}

@(private)
json_f64 :: proc(obj: json.Object, key: string, def: f64) -> f64 {
	v, ok := obj[key]
	if !ok {
		return def
	}
	return json_num_val(v, def)
}

@(private)
json_bool :: proc(obj: json.Object, key: string, def: bool) -> bool {
	v, ok := obj[key]
	if !ok {
		return def
	}
	if b, bok := v.(json.Boolean); bok {
		return bool(b)
	}
	if s, sok := v.(json.String); sok {
		switch strings.to_lower(string(s), context.temp_allocator) {
		case "1", "true", "yes", "on":
			return true
		case "0", "false", "no", "off":
			return false
		}
	}
	return def
}

@(private)
json_num_val :: proc(v: json.Value, def: f64 = 0) -> f64 {
	#partial switch t in v {
	case json.Integer:
		return f64(t)
	case json.Float:
		return f64(t)
	case json.String:
		n, ok := strconv.parse_f64(string(t))
		if ok {
			return n
		}
	}
	return def
}

@(private)
json_f64s :: proc(obj: json.Object, key: string) -> []f64 {
	v, ok := obj[key]
	if !ok {
		return {}
	}
	if s, sok := v.(json.String); sok {
		parts := strings.split(string(s), ",", context.temp_allocator)
		out := make([]f64, len(parts), context.temp_allocator)
		n := 0
		for p in parts {
			f, fok := strconv.parse_f64(strings.trim_space(p))
			if fok {
				out[n] = f
				n += 1
			}
		}
		return out[:n]
	}
	arr, aok := v.(json.Array)
	if !aok {
		return {}
	}
	out := make([]f64, len(arr), context.temp_allocator)
	for item, i in arr {
		out[i] = json_num_val(item)
	}
	return out
}

@(private)
json_color :: proc(obj: json.Object, key: string) -> (ui.Color, bool) {
	s, ok := json_str(obj, key)
	if !ok || len(s) == 0 {
		return {}, false
	}
	return ui.color_parse(s)
}
