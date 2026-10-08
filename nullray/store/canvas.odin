// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Persisted agent canvas apps (show_view panel schemas).

Stored as JSON under <config>/canvases/<id>.json with a small envelope:
  magic, version, id, title, saved_at, schema

Corrupt files fail closed with clear errors. IDs are sanitized.
*/

package store

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"
import "nullray:sandbox"

CANVAS_DIR_NAME :: "canvases"
CANVAS_MAGIC :: "nullray-canvas"
CANVAS_VERSION :: 1
CANVAS_MAX_SCHEMA_BYTES :: 64 * 1024
CANVAS_MAX_ID_LEN :: 64

canvas_dir :: proc(allocator := context.allocator) -> string {
	base := sandbox.resolve_config_dir(context.temp_allocator)
	joined, err := filepath.join({base, CANVAS_DIR_NAME}, allocator)
	if err != nil {
		return fmt.aprintf("%s/%s", base, CANVAS_DIR_NAME, allocator = allocator)
	}
	return joined
}

ensure_canvas_dir :: proc() -> bool {
	dir := canvas_dir(context.temp_allocator)
	_ = sandbox.mkdir_all(dir)
	return true
}

canvas_id_sanitize :: proc(raw: string, allocator := context.allocator) -> string {
	s := sanitize_name(raw)
	if len(s) == 0 {
		s = "canvas"
	}
	if len(s) > CANVAS_MAX_ID_LEN {
		s = s[:CANVAS_MAX_ID_LEN]
	}
	return strings.clone(s, allocator)
}

canvas_path :: proc(id: string, allocator := context.allocator) -> string {
	ensure_canvas_dir()
	safe := canvas_id_sanitize(id, context.temp_allocator)
	dir := canvas_dir(context.temp_allocator)
	joined, err := filepath.join({dir, fmt.tprintf("%s.json", safe)}, allocator)
	if err != nil {
		return fmt.aprintf("%s/%s.json", dir, safe, allocator = allocator)
	}
	return joined
}

Canvas_Info :: struct {
	id:       string,
	title:    string,
	path:     string,
	saved_at: i64,
}

canvas_info_destroy :: proc(info: ^Canvas_Info) {
	delete(info.id)
	delete(info.title)
	delete(info.path)
	info^ = {}
}

canvas_infos_destroy :: proc(items: []Canvas_Info) {
	for &it in items {
		canvas_info_destroy(&it)
	}
	delete(items)
}

// Save a raw show_view schema blob. Returns owned id and empty err on success.
canvas_save :: proc(
	id_hint: string,
	title: string,
	schema_json: string,
	allocator := context.allocator,
) -> (id: string, err: string) {
	raw := strings.trim_space(schema_json)
	if len(raw) == 0 {
		return "", strings.clone("empty canvas schema", allocator)
	}
	if len(raw) > CANVAS_MAX_SCHEMA_BYTES {
		return "", strings.clone("canvas schema too large", allocator)
	}
	// Reject non-object JSON up front.
	if !strings.has_prefix(raw, "{") {
		return "", strings.clone("canvas schema must be a JSON object", allocator)
	}
	doc, perr := json.parse_string(raw, .JSON, allocator = context.temp_allocator)
	if perr != nil {
		return "", strings.clone("canvas schema is not valid JSON", allocator)
	}
	#partial switch v in doc {
	case json.Object:
	case:
		return "", strings.clone("canvas schema must be a JSON object", allocator)
	}

	hint := strings.trim_space(id_hint)
	if len(hint) == 0 {
		hint = strings.trim_space(title)
	}
	if len(hint) == 0 {
		hint = "canvas"
	}
	safe := canvas_id_sanitize(hint, context.temp_allocator)
	path := canvas_path(safe, context.temp_allocator)
	ts := time.to_unix_seconds(time.now())
	title_s := strings.trim_space(title)
	if len(title_s) == 0 {
		title_s = safe
	}
	// Escape by embedding schema as a JSON string value via hand-built envelope.
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	strings.write_string(&b, `{"magic":"`)
	strings.write_string(&b, CANVAS_MAGIC)
	strings.write_string(&b, `","version":`)
	fmt.sbprintf(&b, "%d", CANVAS_VERSION)
	strings.write_string(&b, `,"id":`)
	canvas_write_json_string(&b, safe)
	strings.write_string(&b, `,"title":`)
	canvas_write_json_string(&b, title_s)
	strings.write_string(&b, `,"saved_at":`)
	fmt.sbprintf(&b, "%d", ts)
	strings.write_string(&b, `,"schema":`)
	// schema is already JSON, embed raw
	strings.write_string(&b, raw)
	strings.write_string(&b, `}`)
	body := strings.to_string(b)
	if !atomic_write_bytes(path, transmute([]u8)body) {
		return "", strings.clone("failed to write canvas file", allocator)
	}
	return strings.clone(safe, allocator), ""
}

// Load schema JSON for a canvas id. Caller owns schema. Safe on corrupt files.
canvas_load :: proc(id: string, allocator := context.allocator) -> (schema: string, title: string, err: string) {
	safe := canvas_id_sanitize(id, context.temp_allocator)
	path := canvas_path(safe, context.temp_allocator)
	data, rerr := os.read_entire_file(path, context.temp_allocator)
	if rerr != nil {
		return "", "", strings.clone("canvas not found", allocator)
	}
	if len(data) == 0 || len(data) > CANVAS_MAX_SCHEMA_BYTES+4096 {
		return "", "", strings.clone("canvas file empty or oversized", allocator)
	}
	doc, perr := json.parse_string(string(data), .JSON, allocator = context.temp_allocator)
	if perr != nil {
		return "", "", strings.clone("corrupt canvas (invalid JSON)", allocator)
	}
	obj, is_obj := doc.(json.Object)
	if !is_obj {
		return "", "", strings.clone("corrupt canvas (not an object)", allocator)
	}
	if m, ok := obj["magic"]; ok {
		if ms, mok := m.(json.String); !mok || string(ms) != CANVAS_MAGIC {
			return "", "", strings.clone("corrupt canvas (bad magic)", allocator)
		}
	} else {
		return "", "", strings.clone("corrupt canvas (missing magic)", allocator)
	}
	ver := 0
	if v, ok := obj["version"]; ok {
		#partial switch t in v {
		case json.Integer:
			ver = int(t)
		case json.Float:
			ver = int(t)
		}
	}
	if ver < 1 || ver > CANVAS_VERSION+10 {
		return "", "", strings.clone("corrupt canvas (unsupported version)", allocator)
	}
	sch_val, sok := obj["schema"]
	if !sok {
		return "", "", strings.clone("corrupt canvas (missing schema)", allocator)
	}
	schema_out: string
	#partial switch s in sch_val {
	case json.Object, json.Array:
		// Re-serialize nested object: dump original substring is hard, encode again.
		// Prefer to keep raw by re-marshaling is not available. Use string clone of pretty print via fmt of keys is wrong.
		// Fallback: write JSON via recursive is heavy. Store as object means we need encode.
		// Simple path: if schema is object, accept by rebuilding from file scan.
		schema_out, err = canvas_extract_schema_raw(string(data), allocator)
		if err != "" {
			return "", "", err
		}
	case json.String:
		schema_out = strings.clone(string(s), allocator)
	case:
		return "", "", strings.clone("corrupt canvas (schema type)", allocator)
	}
	if len(strings.trim_space(schema_out)) == 0 || !strings.has_prefix(strings.trim_space(schema_out), "{") {
		delete(schema_out)
		return "", "", strings.clone("corrupt canvas (empty schema)", allocator)
	}
	// Validate parseable
	_, verr := json.parse_string(schema_out, .JSON, allocator = context.temp_allocator)
	if verr != nil {
		delete(schema_out)
		return "", "", strings.clone("corrupt canvas (schema JSON)", allocator)
	}
	title_out := safe
	if t, tok := obj["title"]; tok {
		if ts, tsok := t.(json.String); tsok && len(string(ts)) > 0 {
			title_out = string(ts)
		}
	}
	return schema_out, strings.clone(title_out, allocator), ""
}

canvas_delete :: proc(id: string) -> bool {
	path := canvas_path(id, context.temp_allocator)
	return os.remove(path) == nil
}

canvas_list :: proc(allocator := context.allocator) -> []Canvas_Info {
	ensure_canvas_dir()
	dir := canvas_dir(context.temp_allocator)
	entries, err := os.read_directory_by_path(dir, -1, context.temp_allocator)
	out := make([dynamic]Canvas_Info, allocator)
	if err != nil {
		return out[:]
	}
	for e in entries {
		name := e.name
		if e.type == .Directory {
			continue
		}
		if !strings.has_suffix(name, ".json") {
			continue
		}
		stem := name[:len(name)-len(".json")]
		path := canvas_path(stem, allocator)
		title := stem
		saved: i64 = 0
		// Best-effort header read
		data, rerr := os.read_entire_file(path, context.temp_allocator)
		if rerr == nil {
			if doc, perr := json.parse_string(string(data), .JSON, allocator = context.temp_allocator); perr == nil {
				if obj, ok := doc.(json.Object); ok {
					if t, tok := obj["title"]; tok {
						if ts, tsok := t.(json.String); tsok {
							title = string(ts)
						}
					}
					if s, sok := obj["saved_at"]; sok {
						#partial switch v in s {
						case json.Integer:
							saved = i64(v)
						case json.Float:
							saved = i64(v)
						}
					}
					// Skip files with wrong magic quietly
					if m, mok := obj["magic"]; mok {
						if ms, msok := m.(json.String); !msok || string(ms) != CANVAS_MAGIC {
							delete(path)
							continue
						}
					}
				}
			}
		}
		append(&out, Canvas_Info{
			id = strings.clone(stem, allocator),
			title = strings.clone(title, allocator),
			path = path,
			saved_at = saved,
		})
	}
	return out[:]
}

canvas_list_text :: proc(allocator := context.allocator) -> string {
	items := canvas_list(context.temp_allocator)
	if len(items) == 0 {
		return strings.clone("no saved canvases (use show_view placement=panel + id, or /canvas save)", allocator)
	}
	b: strings.Builder
	strings.builder_init(&b, allocator)
	strings.write_string(&b, "canvases:\n")
	for it in items {
		if it.saved_at > 0 {
			fmt.sbprintf(&b, "  %s  %s  (saved %d)\n", it.id, it.title, it.saved_at)
		} else {
			fmt.sbprintf(&b, "  %s  %s\n", it.id, it.title)
		}
	}
	return strings.to_string(b)
}

@(private)
canvas_write_json_string :: proc(b: ^strings.Builder, s: string) {
	strings.write_byte(b, '"')
	for i := 0; i < len(s); i += 1 {
		c := s[i]
		switch c {
		case '"', '\\':
			strings.write_byte(b, '\\')
			strings.write_byte(b, c)
		case '\n':
			strings.write_string(b, "\\n")
		case '\r':
			strings.write_string(b, "\\r")
		case '\t':
			strings.write_string(b, "\\t")
		case:
			if c < 0x20 {
				fmt.sbprintf(b, "\\u%04x", c)
			} else {
				strings.write_byte(b, c)
			}
		}
	}
	strings.write_byte(b, '"')
}

// Pull the raw schema object after "schema": from the envelope without re-encoding.
@(private)
canvas_extract_schema_raw :: proc(file: string, allocator := context.allocator) -> (string, string) {
	key := `"schema"`
	idx := strings.index(file, key)
	if idx < 0 {
		return "", strings.clone("corrupt canvas (schema key)", allocator)
	}
	rest := file[idx+len(key):]
	// skip whitespace and colon
	i := 0
	for i < len(rest) && (rest[i] == ' ' || rest[i] == '\t' || rest[i] == '\n' || rest[i] == '\r') {
		i += 1
	}
	if i >= len(rest) || rest[i] != ':' {
		return "", strings.clone("corrupt canvas (schema colon)", allocator)
	}
	i += 1
	for i < len(rest) && (rest[i] == ' ' || rest[i] == '\t' || rest[i] == '\n' || rest[i] == '\r') {
		i += 1
	}
	if i >= len(rest) || rest[i] != '{' {
		return "", strings.clone("corrupt canvas (schema object)", allocator)
	}
	start := i
	depth := 0
	in_str := false
	esc := false
	for i < len(rest) {
		c := rest[i]
		if in_str {
			if esc {
				esc = false
			} else if c == '\\' {
				esc = true
			} else if c == '"' {
				in_str = false
			}
			i += 1
			continue
		}
		switch c {
		case '"':
			in_str = true
		case '{':
			depth += 1
		case '}':
			depth -= 1
			if depth == 0 {
				return strings.clone(rest[start:i+1], allocator), ""
			}
		}
		i += 1
	}
	return "", strings.clone("corrupt canvas (unterminated schema)", allocator)
}
