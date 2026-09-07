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

destroy_entries :: proc(entries: ^[dynamic]Entry) {
	if entries == nil {
		return
	}
	for e in entries {
		delete(e.key)
		delete(e.value)
	}
	delete(entries^)
	entries^ = nil
}

workspace_root :: proc(allocator := context.allocator) -> string {
	st := sandbox.state()
	if st != nil && len(st.workspace) > 0 {
		return strings.clone(st.workspace, allocator)
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
	dir := memory_dir(context.temp_allocator)
	path, err := filepath.join({dir, "entries.jsonl"}, context.temp_allocator)
	if err != nil {
		return entries
	}
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
				delete(existing.value)
				existing.value = entry.value
				existing.updated_at = entry.updated_at
				delete(entry.key)
				replaced = true
				break
			}
		}
		if !replaced && len(entries) < constants.MAX_MEMORY_ENTRIES {
			append(&entries, entry)
		} else if !replaced {
			delete(entry.key)
			delete(entry.value)
		}
	}
	return entries
}

digest_from_entries :: proc(entries: []Entry, max_chars: int, allocator := context.allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	for e in entries {
		line := fmt.tprintf("- %s: %s\n", e.key, e.value)
		if len(line) > 240 {
			line = fmt.tprintf("- %s: %s...\n", e.key, e.value[:min(200, len(e.value))])
		}
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
	return digest_from_entries(entries[:], max_chars, allocator)
}

Get :: proc(key: string, allocator := context.allocator) -> (string, string) {
	trimmed := strings.trim_space(key)
	entries := load_entries(context.temp_allocator)
	for e in entries {
		if e.key == trimmed {
			return strings.clone(e.value, allocator), ""
		}
	}
	return "", fmt.aprintf("unknown memory key: %s", trimmed, allocator = allocator)
}

List :: proc(filter: string = "", allocator := context.allocator) -> string {
	entries := load_entries(context.temp_allocator)
	b: strings.Builder
	strings.builder_init(&b, allocator)
	count := 0
	for e in entries {
		if len(filter) > 0 && !strings.contains(e.key, filter) && !strings.contains(e.value, filter) {
			continue
		}
		fmt.sbprintf(&b, "%s\n", e.key)
		count += 1
	}
	if count == 0 {
		strings.write_string(&b, "(empty)")
	}
	return strings.to_string(b)
}

Put :: proc(key, value: string, allocator := context.allocator) -> (string, string) {
	if ephemeral() {
		return strings.clone("memory write skipped in ephemeral mode", allocator), ""
	}
	trimmed := strings.trim_space(key)
	if len(trimmed) == 0 {
		return "", strings.clone("empty memory key", allocator)
	}
	if len(value) == 0 {
		return "", strings.clone("empty memory value", allocator)
	}
	if sandbox.value_looks_secret(value) {
		return "", strings.clone("refusing to store secret-shaped memory value", allocator)
	}
	entries := load_entries(context.temp_allocator)
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
	if err := os.make_directory_all(dir); err != nil {
		return "", fmt.aprintf("memory directory failed: %v", err, allocator = allocator)
	}
	path, _ := filepath.join({dir, "entries.jsonl"}, context.temp_allocator)
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
	digest := digest_from_entries(reloaded[:], constants.MAX_MEMORY_PROMPT_CHARS, context.temp_allocator)
	digest_path, _ := filepath.join({dir, "MEMORY.md"}, context.temp_allocator)
	body := fmt.tprintf("# Project memory\n\n%s", digest)
	if err := os.write_entire_file(digest_path, transmute([]u8)body); err != nil {
		return "", fmt.aprintf("memory digest write failed: %v", err, allocator = allocator)
	}
	return strings.clone("ok", allocator), ""
}
