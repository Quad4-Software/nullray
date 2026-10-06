// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Todo store persistence: .nullray/todos/<session>.json written atomically on
each mutation, loaded lazily on first access. Empty session ids stay
memory-only.
*/

package todo

import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "nullray:constants"
import "nullray:sandbox"

@(private)
workspace_root :: proc(allocator := context.allocator) -> string {
	st := sandbox.state()
	if st != nil && len(st.workspace) > 0 {
		return strings.clone(st.workspace, allocator)
	}
	if v, ok := os.lookup_env(constants.ENV_WORKSPACE, context.temp_allocator); ok && len(v) > 0 {
		return strings.clone(v, allocator)
	}
	if cwd, err := os.get_working_directory(allocator); err == nil {
		return cwd
	}
	return strings.clone(".", allocator)
}

// Session ids are file stems already, but keep the guard cheap and total.
@(private)
sanitize_id :: proc(session_id: string, allocator := context.allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	for ch in session_id {
		switch ch {
		case '/', '\\', ':', '*', '?', '"', '<', '>', '|', '\x00':
			strings.write_rune(&b, '_')
		case:
			strings.write_rune(&b, ch)
		}
	}
	out := strings.to_string(b)
	if len(out) == 0 {
		delete(out)
		return strings.clone("_", allocator)
	}
	return out
}

// Empty when the session id is empty (memory-only store).
@(private)
persist_path :: proc(session_id: string, allocator := context.allocator) -> string {
	if len(session_id) == 0 {
		return ""
	}
	root := workspace_root(context.temp_allocator)
	safe := sanitize_id(session_id, context.temp_allocator)
	name := fmt.aprintf("%s.json", safe, allocator = context.temp_allocator)
	path, err := filepath.join({root, constants.TODO_DIR, name}, allocator)
	if err != nil {
		return ""
	}
	return path
}

/*
JSON string escape onto a builder. fmt %q is NOT JSON: it emits \a, \v and
\xNN escapes that parsers reject, so one control char in an item would
corrupt the whole store file. Byte-level pass-through keeps valid UTF-8
intact and escapes the control range, so items round-trip through
json.parse unchanged.
*/
@(private)
write_json_string :: proc(b: ^strings.Builder, s: string) {
	strings.write_byte(b, '"')
	for i in 0 ..< len(s) {
		c := s[i]
		switch c {
		case '"':
			strings.write_string(b, `\"`)
		case '\\':
			strings.write_string(b, `\\`)
		case '\n':
			strings.write_string(b, `\n`)
		case '\r':
			strings.write_string(b, `\r`)
		case '\t':
			strings.write_string(b, `\t`)
		case '\b':
			strings.write_string(b, `\b`)
		case '\f':
			strings.write_string(b, `\f`)
		case:
			if c < 0x20 {
				fmt.sbprintf(b, `\u%04x`, c)
			} else {
				strings.write_byte(b, c)
			}
		}
	}
	strings.write_byte(b, '"')
}

// Temp-plus-rename so a crash mid-write never leaves a truncated file.
@(private)
write_atomic :: proc(path: string, data: []u8) -> bool {
	tmp := fmt.aprintf("%s.tmp.%d", path, os.get_pid(), allocator = context.temp_allocator)
	if werr := os.write_entire_file(tmp, data); werr != nil {
		_ = os.remove(tmp)
		return false
	}
	if rerr := os.rename(tmp, path); rerr != nil {
		_ = os.remove(path)
		if rerr2 := os.rename(tmp, path); rerr2 != nil {
			_ = os.remove(tmp)
			return false
		}
	}
	return true
}

@(private)
save_store :: proc(s: ^Store, session_id: string) {
	path := persist_path(session_id, context.temp_allocator)
	if len(path) == 0 {
		return
	}
	dir, derr := filepath.join({workspace_root(context.temp_allocator), constants.TODO_DIR}, context.temp_allocator)
	if derr == nil {
		_ = sandbox.mkdir_all(dir)
	}
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	strings.write_byte(&b, '{')
	fmt.sbprintf(&b, `"seq":%d,"items":[`, s.next_seq)
	for it, i in s.items {
		if i > 0 {
			strings.write_byte(&b, ',')
		}
		strings.write_byte(&b, '{')
		strings.write_string(&b, `"id":`)
		write_json_string(&b, it.id)
		strings.write_string(&b, `,"text":`)
		write_json_string(&b, it.text)
		strings.write_string(&b, `,"status":`)
		write_json_string(&b, status_name(it.status))
		fmt.sbprintf(&b, `,"seq":%d,"updated":%d`, it.seq, it.updated_epoch)
		if len(it.blocked_on) > 0 {
			strings.write_string(&b, `,"blocked_on":[`)
			for ref, j in it.blocked_on {
				if j > 0 {
					strings.write_byte(&b, ',')
				}
				write_json_string(&b, ref)
			}
			strings.write_byte(&b, ']')
		}
		if len(it.note) > 0 {
			strings.write_string(&b, `,"note":`)
			write_json_string(&b, it.note)
		}
		strings.write_byte(&b, '}')
	}
	strings.write_string(&b, "]}")
	body := strings.to_string(b)
	if !write_atomic(path, transmute([]u8)body) {
		// Persistence is best effort; the in-memory list still works.
		return
	}
}

@(private)
json_str_field :: proc(obj: json.Object, key: string, allocator := context.allocator) -> string {
	if v, ok := obj[key]; ok {
		if s, sok := v.(json.String); sok {
			return strings.clone(string(s), allocator)
		}
	}
	return ""
}

@(private)
json_str_list :: proc(obj: json.Object, key: string, allocator := context.allocator) -> [dynamic]string {
	out := make([dynamic]string, allocator)
	if v, ok := obj[key]; ok {
		if arr, aok := v.(json.Array); aok {
			for elem in arr {
				if s, sok := elem.(json.String); sok {
					append(&out, strings.clone(string(s), allocator))
				}
			}
		}
	}
	return out
}

@(private)
load_store :: proc(s: ^Store, session_id: string) {
	path := persist_path(session_id, context.temp_allocator)
	if len(path) == 0 {
		return
	}
	data, rerr := os.read_entire_file(path, context.temp_allocator)
	if rerr != nil {
		return
	}
	doc, perr := json.parse_string(string(data), .JSON, allocator = context.temp_allocator)
	if perr != nil {
		return
	}
	obj, ok := doc.(json.Object)
	if !ok {
		return
	}
	if v, found := obj["seq"]; found {
		#partial switch n in v {
		case json.Integer:
			s.next_seq = int(n)
		case json.Float:
			s.next_seq = int(n)
		}
	}
	arr, aok := obj["items"].(json.Array)
	if !aok {
		return
	}
	for elem in arr {
		eo, eok := elem.(json.Object)
		if !eok {
			continue
		}
		it: Item
		it.id = json_str_field(eo, "id", store_alloc())
		it.text = json_str_field(eo, "text", store_alloc())
		if len(it.id) == 0 || len(it.text) == 0 {
			delete(it.id, store_alloc())
			delete(it.text, store_alloc())
			continue
		}
		st, _ := status_from_string(json_str_field(eo, "status", context.temp_allocator))
		it.status = st
		it.blocked_on = json_str_list(eo, "blocked_on", store_alloc())
		it.note = json_str_field(eo, "note", store_alloc())
		if v, found := eo["seq"]; found {
			#partial switch n in v {
			case json.Integer:
				it.seq = int(n)
			case json.Float:
				it.seq = int(n)
			}
		}
		if v, found := eo["updated"]; found {
			#partial switch n in v {
			case json.Integer:
				it.updated_epoch = i64(n)
			case json.Float:
				it.updated_epoch = i64(n)
			}
		}
		append(&s.items, it)
		if it.seq >= s.next_seq {
			s.next_seq = it.seq + 1
		}
	}
}
