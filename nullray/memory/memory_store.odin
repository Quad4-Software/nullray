// SPDX-License-Identifier: 0BSD
/*
Project memory persistence and index sync.
*/

package memory

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "nullray:constants"

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
