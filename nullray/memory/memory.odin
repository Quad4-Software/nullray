// SPDX-License-Identifier: 0BSD
/*
Project-scoped durable memory.
*/

package memory

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"
import "nullray:constants"
import "nullray:sandbox"

Entry :: struct {
	key:        string,
	value:      string,
	updated_at: i64,
}

Search_Hit :: struct {
	entry:      Entry,
	key_match:  bool,
	value_match: bool,
}

KEY_PREFIXES :: []string{"pref.", "build.", "arch.", "debt.", "user."}

destroy_entries :: proc(entries: ^[dynamic]Entry, allocator := context.allocator) {
	if entries == nil {
		return
	}
	for e in entries {
		delete(e.key, allocator)
		delete(e.value, allocator)
	}
	delete(entries^)
	entries^ = nil
}

ensure_memory_dir :: proc(path: string) -> string {
	_ = os.make_directory_all(path)
	return ""
}

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

memory_dir :: proc(allocator := context.allocator) -> string {
	root := workspace_root(context.temp_allocator)
	path, err := filepath.join({root, constants.MEMORY_DIR}, allocator)
	if err != nil {
		return strings.clone(constants.MEMORY_DIR, allocator)
	}
	return path
}

entries_path :: proc(allocator := context.allocator) -> string {
	dir := memory_dir(context.temp_allocator)
	path, err := filepath.join({dir, "entries.jsonl"}, allocator)
	if err != nil {
		return strings.clone("entries.jsonl", allocator)
	}
	return path
}

topics_dir :: proc(allocator := context.allocator) -> string {
	dir := memory_dir(context.temp_allocator)
	path, err := filepath.join({dir, "topics"}, allocator)
	if err != nil {
		return strings.clone("topics", allocator)
	}
	return path
}

memory_index_path :: proc(allocator := context.allocator) -> string {
	dir := memory_dir(context.temp_allocator)
	path, err := filepath.join({dir, "MEMORY.md"}, allocator)
	if err != nil {
		return strings.clone("MEMORY.md", allocator)
	}
	return path
}

ephemeral :: proc() -> bool {
	if value, ok := os.lookup_env(constants.ENV_EPHEMERAL, context.temp_allocator); ok {
		switch strings.to_lower(value, context.temp_allocator) {
		case "1", "true", "yes", "on":
			return true
		}
	}
	return false
}

auto_enabled :: proc() -> bool {
	if value, ok := os.lookup_env(constants.ENV_AUTO_MEMORY, context.temp_allocator); ok {
		switch strings.to_lower(value, context.temp_allocator) {
		case "0", "false", "no", "off", "disable", "disabled":
			return false
		}
	}
	return true
}

sanitize_topic_name :: proc(key: string, allocator := context.allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	for ch in key {
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

key_prefix_warn :: proc(key: string, allocator := context.allocator) -> string {
	for prefix in KEY_PREFIXES {
		if strings.has_prefix(key, prefix) {
			return ""
		}
	}
	return strings.clone(
		"unconventional key prefix (prefer pref., build., arch., debt., or user.)",
		allocator,
	)
}

validate_put_sizes :: proc(key, value: string, allocator := context.allocator) -> string {
	if len(key) > constants.MAX_MEMORY_KEY_CHARS {
		return fmt.aprintf(
			"memory key too long (max %d)",
			constants.MAX_MEMORY_KEY_CHARS,
			allocator = allocator,
		)
	}
	if len(value) > constants.MAX_MEMORY_VALUE_CHARS {
		return fmt.aprintf(
			"memory value too long (max %d)",
			constants.MAX_MEMORY_VALUE_CHARS,
			allocator = allocator,
		)
	}
	return ""
}

format_updated_at :: proc(ts: i64, include_staleness: bool, allocator := context.allocator) -> string {
	if ts <= 0 {
		return strings.clone("unknown", allocator)
	}
	t := time.unix(ts, 0)
	buf: [16]u8
	date := time.to_string_yyyy_mm_dd(t, buf[:])
	out := strings.clone(date, allocator)
	if include_staleness && is_stale(ts) {
		stale := fmt.aprintf("%s (stale)", out, allocator = allocator)
		delete(out)
		return stale
	}
	return out
}

is_stale :: proc(ts: i64) -> bool {
	if ts <= 0 {
		return false
	}
	now := time.time_to_unix(time.now())
	age_days := (now - ts) / 86_400
	return age_days > constants.MEMORY_STALE_DAYS
}

one_line_summary :: proc(value: string, max_chars: int, allocator := context.allocator) -> string {
	flat, _ := strings.replace_all(value, "\n", " ", context.temp_allocator)
	flat, _ = strings.replace_all(flat, "\r", " ", context.temp_allocator)
	flat = strings.trim_space(flat)
	if len(flat) <= max_chars {
		return strings.clone(flat, allocator)
	}
	return fmt.aprintf("%s...", flat[:max_chars], allocator = allocator)
}

preview_value :: proc(value: string, allocator := context.allocator) -> string {
	return one_line_summary(value, constants.MEMORY_LIST_PREVIEW_CHARS, allocator)
}

parse_entry :: proc(line: string, allocator := context.allocator) -> (Entry, bool) {
	doc, err := json.parse_string(line, .JSON, allocator = context.temp_allocator)
	if err != nil {
		return {}, false
	}
	obj, ok := doc.(json.Object)
	if !ok {
		return {}, false
	}
	key_value, key_ok := obj["key"]
	value_value, value_ok := obj["value"]
	if !key_ok || !value_ok {
		return {}, false
	}
	key, key_string := key_value.(json.String)
	value, value_string := value_value.(json.String)
	if !key_string || !value_string {
		return {}, false
	}
	updated: i64
	if raw, found := obj["updated"]; found {
		#partial switch v in raw {
		case json.Integer:
			updated = i64(v)
		case json.Float:
			updated = i64(v)
		}
	}
	return Entry{
		key = strings.clone(string(key), allocator),
		value = strings.clone(string(value), allocator),
		updated_at = updated,
	}, true
}
