// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package schedule

import "core:hash"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:slice"
import "core:strings"
import "core:sync"
import "core:time"
import "nullray:constants"
import "nullray:sandbox"

watch_state_load :: proc(id: int, allocator := context.allocator) -> (st: Watch_State, ok: bool) {
	path := watch_state_path(id, context.temp_allocator)
	data, rerr := os.read_entire_file(path, context.temp_allocator)
	if rerr != nil {
		return {}, false
	}
	doc, perr := json.parse_string(string(data), .JSON, allocator = context.temp_allocator)
	if perr != nil {
		return {}, false
	}
	obj, is_obj := doc.(json.Object)
	if !is_obj {
		return {}, false
	}
	st.id = id
	if s, s_ok := obj["title"].(json.String); s_ok {
		st.title = strings.clone(string(s), allocator)
	}
	if s, s_ok := obj["fingerprint"].(json.String); s_ok {
		st.fingerprint = strings.clone(string(s), allocator)
	}
	st.runs = int(json_int(obj["runs"]))
	st.checks = int(json_int(obj["checks"]))
	st.hits = int(json_int(obj["hits"]))
	st.tokens = json_int(obj["tokens"])
	st.max_tokens = json_int(obj["max_tokens"])
	st.created = json_int(obj["created"])
	st.last_run = json_int(obj["last_run"])
	st.exhausted = json_bool(obj["exhausted"])
	if arr, a_ok := obj["seen"].(json.Array); a_ok {
		st.seen = make([dynamic]string, 0, len(arr), allocator)
		for elem in arr {
			if s, s_ok := elem.(json.String); s_ok {
				append(&st.seen, strings.clone(string(s), allocator))
			}
		}
	}
	return st, true
}

watch_state_save :: proc(st: ^Watch_State) -> string {
	dir := watch_dir(st.id, context.temp_allocator)
	// mkdir_all reports Exist for an existing dir, that is success here.
	if merr := sandbox.mkdir_all(dir); merr != nil && merr != .Exist {
		return fmt.aprintf("watch dir: %v", merr)
	}
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, `{"id":`)
	fmt.sbprintf(&b, "%d", st.id)
	strings.write_string(&b, `,"title":"`)
	json_escape(st.title, &b)
	strings.write_string(&b, `","fingerprint":"`)
	json_escape(st.fingerprint, &b)
	fmt.sbprintf(
		&b,
		`","runs":%d,"checks":%d,"hits":%d,"tokens":%d,"max_tokens":%d,"created":%d,"last_run":%d,"exhausted":%v,"seen":[`,
		st.runs, st.checks, st.hits, st.tokens, st.max_tokens, st.created, st.last_run, st.exhausted,
	)
	for s, i in st.seen {
		if i > 0 {
			strings.write_byte(&b, ',')
		}
		strings.write_byte(&b, '"')
		json_escape(s, &b)
		strings.write_byte(&b, '"')
	}
	strings.write_string(&b, `]}`)
	path := watch_state_path(st.id, context.temp_allocator)
	tmp := fmt.tprintf("%s.tmp.%d", path, os.get_pid())
	if werr := os.write_entire_file(tmp, transmute([]u8)strings.to_string(b)); werr != nil {
		return fmt.aprintf("watch state write: %v", werr)
	}
	if rerr := os.rename(tmp, path); rerr != nil {
		_ = os.remove(path)
		if rerr2 := os.rename(tmp, path); rerr2 != nil {
			_ = os.remove(tmp)
			return fmt.aprintf("watch state rename: %v", rerr2)
		}
	}
	return ""
}

// Set fingerprint on the sorted item set so result reordering does not
// register as a change.
watch_fingerprint :: proc(items: []string, allocator := context.allocator) -> string {
	sorted := make([]string, len(items), context.temp_allocator)
	copy(sorted, items)
	slice.sort(sorted)
	h: u64 = 0xcbf29ce484222325
	for s in sorted {
		h = hash.fnv64a(transmute([]u8)s, h)
		h = hash.fnv64a(transmute([]u8)string("\x1f"), h)
	}
	return fmt.aprintf("%016x", h, allocator = allocator)
}

@(private)
seen_contains :: proc(st: ^Watch_State, item: string) -> bool {
	for s in st.seen {
		if s == item {
			return true
		}
	}
	return false
}

// Stable string key for one items element. Objects prefer an id-like
// field and otherwise serialize as sorted k=v pairs.
@(private)
watch_item_key :: proc(v: json.Value, allocator := context.allocator) -> string {
	#partial switch val in v {
	case json.String:
		return strings.clone(string(val), allocator)
	case json.Integer:
		return fmt.aprintf("%d", i64(val), allocator = allocator)
	case json.Float:
		return fmt.aprintf("%g", f64(val), allocator = allocator)
	case json.Boolean:
		return strings.clone(bool(val) ? "true" : "false", allocator)
	case json.Array:
		parts := make([dynamic]string, context.temp_allocator)
		for elem in val {
			k := watch_item_key(elem, context.temp_allocator)
			if len(k) > 0 {
				append(&parts, k)
			}
		}
		return strings.clone(strings.join(parts[:], ",", context.temp_allocator), allocator)
	case json.Object:
		for key in ([]string{"id", "cve", "cve_id", "url", "link", "title", "name"}) {
			if s, s_ok := val[key].(json.String); s_ok && len(s) > 0 {
				return strings.clone(string(s), allocator)
			}
		}
		keys := make([dynamic]string, context.temp_allocator)
		for k in val {
			append(&keys, k)
		}
		slice.sort(keys[:])
		b: strings.Builder
		strings.builder_init(&b, context.temp_allocator)
		for k in keys {
			elem := watch_item_key(val[k], context.temp_allocator)
			fmt.sbprintf(&b, "%s=%s;", k, elem)
		}
		return strings.clone(strings.to_string(b), allocator)
	}
	return ""
}

// Normalize the tool's items field (array of any JSON values, a string
// carrying a JSON array, or a comma/newline list) into id strings.
watch_items_normalize :: proc(v: json.Value, allocator := context.allocator) -> (items: []string, err: string) {
	out := make([dynamic]string, allocator)
	#partial switch val in v {
	case json.Array:
		for elem in val {
			k := watch_item_key(elem, context.temp_allocator)
			if len(strings.trim_space(k)) > 0 {
				append(&out, strings.clone(strings.trim_space(k), allocator))
			}
		}
	case json.String:
		raw := strings.trim_space(string(val))
		if strings.has_prefix(raw, "[") {
			if doc, perr := json.parse_string(raw, .JSON, allocator = context.temp_allocator); perr == nil {
				if arr, a_ok := doc.(json.Array); a_ok {
					for elem in arr {
						k := watch_item_key(elem, context.temp_allocator)
						if len(strings.trim_space(k)) > 0 {
							append(&out, strings.clone(strings.trim_space(k), allocator))
						}
					}
					return out[:], ""
				}
			}
		}
		flat, _ := strings.replace_all(raw, "\n", ",", context.temp_allocator)
		for part in strings.split(flat, ",", context.temp_allocator) {
			t := strings.trim_space(part)
			if len(t) > 0 {
				append(&out, strings.clone(t, allocator))
			}
		}
	case json.Null:
	case:
		for s in out {
			delete(s, allocator)
		}
		delete(out)
		return nil, strings.clone("items must be a JSON array", allocator)
	}
	return out[:], ""
}

// Append one digest entry for a delta run.
@(private)
watch_append_digest :: proc(id: int, note: string, items: []string, now: i64) -> string {
	dir := watch_dir(id, context.temp_allocator)
	if merr := sandbox.mkdir_all(dir); merr != nil && merr != .Exist {
		return fmt.aprintf("watch dir: %v", merr)
	}
	path := watch_digest_path(id, context.temp_allocator)
	f, oerr := os.open(path, os.O_WRONLY | os.O_CREATE | os.O_APPEND)
	if oerr != nil {
		return fmt.aprintf("digest open: %v", oerr)
	}
	defer os.close(f)
	t := time.unix(now, 0)
	buf: [16]u8
	date := time.to_string_yyyy_mm_dd(t, buf[:])
	h, m, _ := time.clock(t)
	b := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&b, "\n## %s %02d:%02d UTC (%d new)\n", date, h, m, len(items))
	flat, _ := strings.replace_all(strings.trim_space(note), "\r", "", context.temp_allocator)
	if len(flat) > 0 {
		fmt.sbprintf(&b, "%s\n", flat)
	}
	for it in items {
		fmt.sbprintf(&b, "- %s\n", it)
	}
	_, werr := os.write_string(f, strings.to_string(b))
	if werr != nil {
		return fmt.aprintf("digest write: %v", werr)
	}
	return ""
}

@(private)
watch_append_digest_note :: proc(id: int, line: string, now: i64) {
	_ = watch_append_digest(id, line, nil, now)
}

/*
The delta gate the agent calls once per run. Diffs items against the
persisted seen set, appends digest entries only on new items, and returns
a report string plus the new-item count. Callers notify only when
new_count > 0.
*/
