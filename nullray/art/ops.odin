// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
JSON art program compiler.

{
  "width": 60, "height": 20, "unicode": true,
  "ops": [
    {"op":"figlet","text":"SHIP","x":2,"y":0,"color":"#00ffcc"},
    {"op":"rect","x":0,"y":6,"w":60,"h":12},
    {"op":"plot","fn":"sin","x":2,"y":7,"w":40,"h":10,"color":"cyan"},
    {"op":"bars","x":44,"y":8,"h":8,"values":[1,3,2,5,4]},
    {"op":"spark","x":2,"y":18,"values":[1,2,3,2,4,5]},
    {"op":"line","x1":0,"y1":0,"x2":10,"y2":5},
    {"op":"circle","cx":50,"cy":5,"r":3,"fill":false},
    {"op":"text","x":2,"y":5,"text":"hello"},
    {"op":"ansi","text":"\\u001b[32mOK\\u001b[0m","x":0,"y":0"}
  ]
}
*/

package art

import "core:encoding/json"
import "core:strconv"
import "core:strings"
import "nullray:ui"

// Render a JSON art program to plain text (and optional ANSI export).
// Caller owns returned strings.
art_render_json :: proc(
	raw: string,
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

	// Single-shot helpers without ops
	if t, tok := json_str(obj, "figlet"); tok && len(t) > 0 {
		fg0, hf0 := json_color(obj, "color")
		_ = canvas_figlet(&c, t, json_int(obj, "x", 0), json_int(obj, "y", 0), fg0, hf0)
	}
	if t, tok := json_str(obj, "text"); tok && len(t) > 0 && !json_has(obj, "ops") {
		fg0, hf0 := json_color(obj, "color")
		canvas_text(&c, json_int(obj, "x", 0), json_int(obj, "y", 0), t, fg0, hf0)
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
			op_name, _ := json_str(op_obj, "op")
			if len(op_name) == 0 {
				op_name, _ = json_str(op_obj, "type")
			}
			op_name = strings.to_lower(op_name, context.temp_allocator)
			fg, has_fg := json_color(op_obj, "color")
			if !has_fg {
				fg, has_fg = json_color(op_obj, "fg")
			}
			switch op_name {
			case "clear":
				canvas_clear(&c)
			case "figlet", "banner":
				txt, _ := json_str(op_obj, "text")
				if len(txt) == 0 {
					txt, _ = json_str(op_obj, "s")
				}
				_ = canvas_figlet(&c, txt, json_int(op_obj, "x", 0), json_int(op_obj, "y", 0), fg, has_fg)
			case "text", "label":
				txt, _ := json_str(op_obj, "text")
				if len(txt) == 0 {
					txt, _ = json_str(op_obj, "s")
				}
				canvas_text(&c, json_int(op_obj, "x", 0), json_int(op_obj, "y", 0), txt, fg, has_fg)
			case "rect", "box":
				canvas_rect(
					&c,
					json_int(op_obj, "x", 0),
					json_int(op_obj, "y", 0),
					json_int(op_obj, "w", json_int(op_obj, "width", 10)),
					json_int(op_obj, "h", json_int(op_obj, "height", 5)),
					json_bool(op_obj, "fill", false),
					fg,
					has_fg,
				)
			case "hline":
				canvas_hline(&c, json_int(op_obj, "x", 0), json_int(op_obj, "y", 0), json_int(op_obj, "w", 10), 0, fg, has_fg)
			case "vline":
				canvas_vline(&c, json_int(op_obj, "x", 0), json_int(op_obj, "y", 0), json_int(op_obj, "h", 5), 0, fg, has_fg)
			case "line":
				canvas_line(
					&c,
					json_int(op_obj, "x1", json_int(op_obj, "x", 0)),
					json_int(op_obj, "y1", json_int(op_obj, "y", 0)),
					json_int(op_obj, "x2", 10),
					json_int(op_obj, "y2", 10),
					0,
					fg,
					has_fg,
				)
			case "circle":
				canvas_circle(
					&c,
					json_int(op_obj, "cx", json_int(op_obj, "x", 0)),
					json_int(op_obj, "cy", json_int(op_obj, "y", 0)),
					json_int(op_obj, "r", json_int(op_obj, "radius", 3)),
					json_bool(op_obj, "fill", false),
					fg,
					has_fg,
				)
			case "bars", "bar":
				vals := json_f64s(op_obj, "values")
				canvas_bars(&c, json_int(op_obj, "x", 0), json_int(op_obj, "y", 0), json_int(op_obj, "h", json_int(op_obj, "height", 8)), vals, fg, has_fg)
			case "spark", "sparkline":
				vals := json_f64s(op_obj, "values")
				canvas_spark(&c, json_int(op_obj, "x", 0), json_int(op_obj, "y", 0), vals, fg, has_fg)
			case "plot", "fn":
				fn, _ := json_str(op_obj, "fn")
				if len(fn) == 0 {
					fn, _ = json_str(op_obj, "f")
				}
				if len(fn) == 0 {
					fn = "sin"
				}
				canvas_plot_fn(
					&c,
					json_int(op_obj, "x", 0),
					json_int(op_obj, "y", 0),
					json_int(op_obj, "w", 40),
					json_int(op_obj, "h", 10),
					fn,
					json_int(op_obj, "samples", 0),
					fg,
					has_fg,
				)
			case "scatter", "xy":
				xs := json_f64s(op_obj, "x")
				if len(xs) == 0 {
					xs = json_f64s(op_obj, "xs")
				}
				ys := json_f64s(op_obj, "y")
				if len(ys) == 0 {
					ys = json_f64s(op_obj, "ys")
				}
				// when both named values
				if len(xs) == 0 || len(ys) == 0 {
					// allow "points":[[x,y],...]
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
					&c,
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
				// unescape common sequences
				txt, _ = strings.replace_all(txt, "\\n", "\n", context.temp_allocator)
				txt, _ = strings.replace_all(txt, "\\e", "\x1b", context.temp_allocator)
				txt, _ = strings.replace_all(txt, "\\x1b", "\x1b", context.temp_allocator)
				txt, _ = strings.replace_all(txt, "\\u001b", "\x1b", context.temp_allocator)
				_ = ansi_blit(&c, txt, json_int(op_obj, "x", 0), json_int(op_obj, "y", 0))
			case "put", "pixel":
				ch_s, _ := json_str(op_obj, "ch")
				r: rune = '#'
				if len(ch_s) > 0 {
					r = rune(ch_s[0])
				}
				canvas_put(&c, json_int(op_obj, "x", 0), json_int(op_obj, "y", 0), r, fg, has_fg)
			case:
				// skip unknown
			}
		}
	}

	plain = canvas_to_string(&c, allocator)
	ansi_out = canvas_to_ansi(&c, allocator)
	if len(strings.trim_space(plain)) == 0 {
		return plain, ansi_out, strings.clone("empty art", allocator)
	}
	return plain, ansi_out, ""
}

// Figlet-only convenience.
art_figlet :: proc(text: string, unicode := true, allocator := context.allocator) -> string {
	return figlet_string(text, unicode, allocator)
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
json_int :: proc(obj: json.Object, key: string, def: int) -> int {
	v, ok := obj[key]
	if !ok {
		return def
	}
	return int(json_num_val(v, f64(def)))
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
		// comma list
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
