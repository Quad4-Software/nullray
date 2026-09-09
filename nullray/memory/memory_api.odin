// SPDX-License-Identifier: 0BSD
/*
Project memory public API.
*/

package memory

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import "core:time"
import "nullray:constants"
import "nullray:sandbox"

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
	if g_on_put != nil {
		g_on_put(trimmed, value)
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
	if g_on_delete != nil {
		g_on_delete(trimmed)
	}
	return strings.clone("ok", allocator), ""
}

Delete :: proc(key: string, allocator := context.allocator) -> (string, string) {
	return delete_key(key, allocator)
}

Forget :: proc(key: string, allocator := context.allocator) -> (string, string) {
	return delete_key(key, allocator)
}
