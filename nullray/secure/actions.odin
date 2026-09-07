// SPDX-License-Identifier: 0BSD
package secure

import "base:runtime"
import "core:path/filepath"
import "core:strings"

audit_actions :: proc(workspace: string, allocator := context.allocator) -> string {
	w: Finding_Writer
	writer_init(&w, allocator)
	walk_files(workspace, workspace, &w, actions_visit, allocator)
	return writer_text(&w)
}

actions_visit :: proc(root, path: string, user: rawptr, allocator: runtime.Allocator) {
	rel := relative_path(root, path)
	if !strings.has_prefix(rel, ".github/workflows/") {
		return
	}
	ext := strings.to_lower(filepath.ext(path), context.temp_allocator)
	if ext != ".yml" && ext != ".yaml" {
		return
	}
	text, ok := read_small_file(path, allocator)
	if !ok {
		return
	}
	defer delete(text)
	w := cast(^Finding_Writer)user
	for line, index in strings.split_lines(text, context.temp_allocator) {
		trimmed := strings.trim_space(line)
		if !strings.has_prefix(trimmed, "#") && strings.contains(trimmed, "pull_request_target") {
			finding(w, "high", "actions", rel, index + 1, "pull_request_target is forbidden")
		}
		uses_index := strings.index(trimmed, "uses:")
		if uses_index < 0 {
			continue
		}
		value := strings.trim_space(trimmed[uses_index + len("uses:"):])
		value = strings.trim(value, "\"'")
		if strings.has_prefix(value, "./") {
			continue
		}
		at := strings.last_index(value, "@")
		if at < 0 {
			finding(w, "high", "actions", rel, index + 1, "action reference has no pinned revision")
			continue
		}
		revision := value[at + 1:]
		if !is_sha40(revision) {
			finding(w, "warn", "actions", rel, index + 1, "action uses a floating tag or non-SHA revision")
		}
	}
}

is_sha40 :: proc(value: string) -> bool {
	if len(value) != 40 {
		return false
	}
	for c in value {
		if !((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')) {
			return false
		}
	}
	return true
}
