// SPDX-License-Identifier: 0BSD
/*
Project-scoped durable memory.
*/

package memory

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
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

load_entries :: proc(allocator := context.allocator) -> [dynamic]Entry {
	entries := make([dynamic]Entry, allocator)
	path := entries_path(context.temp_allocator)
	data, read_err := os.read_entire_file(path, context.temp_allocator)
	if read_err != nil {
		return entries
	}
	for line in strings.split_lines(string(data), context.temp_allocator) {
		if len(strings.trim_space(line)) == 0 {
			continue
		}
		entry, ok := parse_entry(line, allocator)
		if !ok {
			continue
		}
		replaced := false
		for &existing in entries {
			if existing.key == entry.key {
				delete(existing.value, allocator)
				existing.value = entry.value
				existing.updated_at = entry.updated_at
				delete(entry.key, allocator)
				replaced = true
				break
			}
		}
		if !replaced && len(entries) < constants.MAX_MEMORY_ENTRIES {
			append(&entries, entry)
		} else if !replaced {
			delete(entry.key, allocator)
			delete(entry.value, allocator)
		}
	}
	return entries
}

count_jsonl_lines :: proc() -> int {
	path := entries_path(context.temp_allocator)
	data, read_err := os.read_entire_file(path, context.temp_allocator)
	if read_err != nil {
		return 0
	}
	count := 0
	for line in strings.split_lines(string(data), context.temp_allocator) {
		if len(strings.trim_space(line)) > 0 {
			count += 1
		}
	}
	return count
}

write_entries_compact :: proc(entries: []Entry) -> string {
	dir := memory_dir(context.temp_allocator)
	if mk_err := ensure_memory_dir(dir); mk_err != "" {
		return mk_err
	}
	path := entries_path(context.temp_allocator)
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	for e in entries {
		line := fmt.tprintf(
			`{{"key":%q,"updated":%d,"value":%q}}` + "\n",
			e.key,
			e.updated_at,
			e.value,
		)
		strings.write_string(&b, line)
	}
	body := strings.to_string(b)
	if err := os.write_entire_file(path, transmute([]u8)body); err != nil {
		return fmt.tprintf("memory compact write failed: %v", err)
	}
	return ""
}

maybe_compact :: proc(entries: []Entry) -> string {
	raw_lines := count_jsonl_lines()
	stale := raw_lines - len(entries)
	if stale <= constants.MEMORY_COMPACT_STALE_LINES {
		return ""
	}
	return write_entries_compact(entries)
}

sync_index_files :: proc(entries: []Entry) -> string {
	dir := memory_dir(context.temp_allocator)
	if mk_err := ensure_memory_dir(dir); mk_err != "" {
		return mk_err
	}
	topics := topics_dir(context.temp_allocator)
	if topics_err := ensure_memory_dir(topics); topics_err != "" {
		return fmt.tprintf("memory topics directory failed: %s", topics_err)
	}

	live_topics := make(map[string]bool, context.temp_allocator)
	defer delete(live_topics)

	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	strings.write_string(&b, "# Project memory\n\n")
	strings.write_string(&b, "Index of durable observations. Edit topic files under topics/ for long values.\n\n")

	for e in entries {
		summary := one_line_summary(e.value, 120, context.temp_allocator)
		updated := format_updated_at(e.updated_at, true, context.temp_allocator)
		fmt.sbprintf(&b, "- `%s` - %s - updated %s\n", e.key, summary, updated)

		if len(e.value) > constants.MEMORY_TOPIC_CHARS {
			topic_name := sanitize_topic_name(e.key, context.temp_allocator)
			topic_path, join_err := filepath.join({topics, fmt.tprintf("%s.md", topic_name)}, context.temp_allocator)
			if join_err != nil {
				continue
			}
			topic_body := fmt.tprintf("# %s\n\n%s\n", e.key, e.value)
			if err := os.write_entire_file(topic_path, transmute([]u8)topic_body); err != nil {
				return fmt.tprintf("memory topic write failed: %v", err)
			}
			live_topics[topic_name] = true
		}
	}

	index_path := memory_index_path(context.temp_allocator)
	if err := os.write_entire_file(index_path, transmute([]u8)strings.to_string(b)); err != nil {
		return fmt.tprintf("memory index write failed: %v", err)
	}

	topic_entries, list_err := os.read_directory_by_path(topics, -1, context.temp_allocator)
	if list_err == nil {
		defer os.file_info_slice_delete(topic_entries, context.temp_allocator)
		for entry in topic_entries {
			if entry.type == .Directory {
				continue
			}
			if !strings.has_suffix(entry.name, ".md") {
				continue
			}
			stem := entry.name[:len(entry.name) - 3]
			if _, ok := live_topics[stem]; !ok {
				remove_path, _ := filepath.join({topics, entry.name}, context.temp_allocator)
				_ = os.remove(remove_path)
			}
		}
	}
	return ""
}

digest_from_entries :: proc(entries: []Entry, max_chars: int, allocator := context.allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	for e in entries {
		updated := format_updated_at(e.updated_at, true, context.temp_allocator)
		summary := preview_value(e.value, context.temp_allocator)
		line := fmt.tprintf("- %s (updated %s): %s\n", e.key, updated, summary)
		if strings.builder_len(b) + len(line) > max_chars {
			break
		}
		strings.write_string(&b, line)
	}
	return strings.to_string(b)
}

Digest :: proc(max_chars := constants.MAX_MEMORY_PROMPT_CHARS, allocator := context.allocator) -> string {
	if !auto_enabled() {
		return strings.clone("", allocator)
	}
	entries := load_entries(context.temp_allocator)
	defer destroy_entries(&entries, context.temp_allocator)
	return digest_from_entries(entries[:], max_chars, allocator)
}

Get :: proc(key: string, allocator := context.allocator) -> (string, string) {
	trimmed := strings.trim_space(key)
	entries := load_entries(context.temp_allocator)
	defer destroy_entries(&entries, context.temp_allocator)
	for e in entries {
		if e.key == trimmed {
			return strings.clone(e.value, allocator), ""
		}
	}
	return "", fmt.aprintf("unknown memory key: %s", trimmed, allocator = allocator)
}

List :: proc(filter: string = "", allocator := context.allocator) -> string {
	entries := load_entries(context.temp_allocator)
	defer destroy_entries(&entries, context.temp_allocator)
	b: strings.Builder
	strings.builder_init(&b, allocator)
	count := 0
	trim_filter := strings.trim_space(filter)
	for e in entries {
		if len(trim_filter) > 0 &&
		   !strings.contains(e.key, trim_filter) &&
		   !strings.contains(e.value, trim_filter) {
			continue
		}
		preview := preview_value(e.value, context.temp_allocator)
		updated := format_updated_at(e.updated_at, true, context.temp_allocator)
		fmt.sbprintf(&b, "%s | %s | %s\n", e.key, preview, updated)
		count += 1
	}
	if count == 0 {
		strings.write_string(&b, "(empty)")
	}
	return strings.to_string(b)
}

search_hits :: proc(query: string, limit: int, allocator := context.allocator) -> [dynamic]Search_Hit {
	hits := make([dynamic]Search_Hit, allocator)
	needle := strings.trim_space(query)
	if len(needle) == 0 {
		return hits
	}
	entries := load_entries(context.temp_allocator)
	defer destroy_entries(&entries, context.temp_allocator)
	lower_needle := strings.to_lower(needle, context.temp_allocator)
	for e in entries {
		key_match := strings.contains(strings.to_lower(e.key, context.temp_allocator), lower_needle)
		value_match := strings.contains(strings.to_lower(e.value, context.temp_allocator), lower_needle)
		if !key_match && !value_match {
			continue
		}
		append(&hits, Search_Hit{
			entry = Entry{
				key = strings.clone(e.key, allocator),
				value = strings.clone(e.value, allocator),
				updated_at = e.updated_at,
			},
			key_match = key_match,
			value_match = value_match,
		})
	}
	slice.sort_by(hits[:], proc(a, b: Search_Hit) -> bool {
		if a.key_match != b.key_match {
			return a.key_match
		}
		if a.entry.updated_at != b.entry.updated_at {
			return a.entry.updated_at > b.entry.updated_at
		}
		return a.entry.key < b.entry.key
	})
	if len(hits) > limit {
		for i in limit ..< len(hits) {
			delete(hits[i].entry.key, allocator)
			delete(hits[i].entry.value, allocator)
		}
		resize(&hits, limit)
	}
	return hits
}

destroy_search_hits :: proc(hits: ^[dynamic]Search_Hit, allocator := context.allocator) {
	if hits == nil {
		return
	}
	for h in hits {
		delete(h.entry.key, allocator)
		delete(h.entry.value, allocator)
	}
	delete(hits^)
	hits^ = nil
}

Search :: proc(query: string, limit: int = constants.MEMORY_SEARCH_DEFAULT_LIMIT, allocator := context.allocator) -> string {
	cap := limit
	if cap <= 0 {
		cap = constants.MEMORY_SEARCH_DEFAULT_LIMIT
	}
	if cap > constants.MEMORY_SEARCH_MAX_LIMIT {
		cap = constants.MEMORY_SEARCH_MAX_LIMIT
	}
	hits := search_hits(query, cap, context.temp_allocator)
	defer destroy_search_hits(&hits, context.temp_allocator)
	b: strings.Builder
	strings.builder_init(&b, allocator)
	if len(hits) == 0 {
		strings.write_string(&b, "(no matches)")
		return strings.to_string(b)
	}
	for h in hits {
		preview := preview_value(h.entry.value, context.temp_allocator)
		updated := format_updated_at(h.entry.updated_at, true, context.temp_allocator)
		match_in := "value"
		if h.key_match {
			match_in = "key"
		}
		fmt.sbprintf(&b, "%s | %s | updated %s | match:%s\n", h.entry.key, preview, updated, match_in)
	}
	return strings.to_string(b)
}

Put :: proc(key, value: string, allocator := context.allocator) -> (string, string) {
	// Project memory is workspace-local under .nullray/memory. Session
	// ephemeral only skips transcripts, not explicit memory_put/delete.
	trimmed := strings.trim_space(key)
	if len(trimmed) == 0 {
		return "", strings.clone("empty memory key", allocator)
	}
	if len(value) == 0 {
		return "", strings.clone("empty memory value", allocator)
	}
	if size_err := validate_put_sizes(trimmed, value, allocator); size_err != "" {
		return "", size_err
	}
	if sandbox.value_looks_secret(value) {
		return "", strings.clone("refusing to store secret-shaped memory value", allocator)
	}
	entries := load_entries(context.temp_allocator)
	defer destroy_entries(&entries, context.temp_allocator)
	found := false
	for e in entries {
		if e.key == trimmed {
			found = true
			break
		}
	}
	if !found && len(entries) >= constants.MAX_MEMORY_ENTRIES {
		return "", strings.clone("memory store full", allocator)
	}
	dir := memory_dir(context.temp_allocator)
	if mk_err := ensure_memory_dir(dir); mk_err != "" {
		return "", strings.clone(mk_err, allocator)
	}
	path := entries_path(context.temp_allocator)
	now := time.time_to_unix(time.now())
	line := fmt.tprintf(`{{"key":%q,"updated":%d,"value":%q}}`+"\n", trimmed, now, value)
	file, open_err := os.open(path, os.O_WRONLY | os.O_CREATE | os.O_APPEND)
	if open_err != nil {
		return "", fmt.aprintf("memory open failed: %v", open_err, allocator = allocator)
	}
	_, write_err := os.write_string(file, line)
	os.close(file)
	if write_err != nil {
		return "", fmt.aprintf("memory write failed: %v", write_err, allocator = allocator)
	}

	reloaded := load_entries(context.temp_allocator)
	if compact_err := maybe_compact(reloaded[:]); compact_err != "" {
		destroy_entries(&reloaded, context.temp_allocator)
		return "", strings.clone(compact_err, allocator)
	}
	destroy_entries(&reloaded, context.temp_allocator)
	reloaded = load_entries(context.temp_allocator)
	defer destroy_entries(&reloaded, context.temp_allocator)
	if sync_err := sync_index_files(reloaded[:]); sync_err != "" {
		return "", strings.clone(sync_err, allocator)
	}

	msg := strings.clone("ok", allocator)
	warn := key_prefix_warn(trimmed, context.temp_allocator)
	if len(warn) > 0 {
		combined := fmt.aprintf("ok (%s)", warn, allocator = allocator)
		delete(msg)
		msg = combined
	}
	return msg, ""
}

delete_key :: proc(key: string, allocator := context.allocator) -> (string, string) {
	trimmed := strings.trim_space(key)
	if len(trimmed) == 0 {
		return "", strings.clone("empty memory key", allocator)
	}
	entries := load_entries(context.temp_allocator)
	defer destroy_entries(&entries, context.temp_allocator)
	found := false
	kept := make([dynamic]Entry, context.temp_allocator)
	for e in entries {
		if e.key == trimmed {
			found = true
			continue
		}
		append(&kept, Entry{
			key = strings.clone(e.key, context.temp_allocator),
			value = strings.clone(e.value, context.temp_allocator),
			updated_at = e.updated_at,
		})
	}
	if !found {
		return "", fmt.aprintf("unknown memory key: %s", trimmed, allocator = allocator)
	}
	if compact_err := write_entries_compact(kept[:]); compact_err != "" {
		return "", strings.clone(compact_err, allocator)
	}
	if sync_err := sync_index_files(kept[:]); sync_err != "" {
		return "", strings.clone(sync_err, allocator)
	}
	return strings.clone("ok", allocator), ""
}

Delete :: proc(key: string, allocator := context.allocator) -> (string, string) {
	return delete_key(key, allocator)
}

Forget :: proc(key: string, allocator := context.allocator) -> (string, string) {
	return delete_key(key, allocator)
}
