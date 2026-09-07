// SPDX-License-Identifier: 0BSD
package secure

import "base:runtime"
import "core:path/filepath"
import "core:strings"

audit_dockerfile :: proc(workspace: string, allocator := context.allocator) -> string {
	w: Finding_Writer
	writer_init(&w, allocator)
	walk_files(workspace, workspace, &w, dockerfile_visit, allocator)
	return writer_text(&w)
}

dockerfile_visit :: proc(root, path: string, user: rawptr, allocator: runtime.Allocator) {
	name := filepath.base(path)
	if name != "Dockerfile" && !strings.has_suffix(name, ".Dockerfile") {
		return
	}
	text, ok := read_small_file(path, allocator)
	if !ok {
		return
	}
	defer delete(text)
	w := cast(^Finding_Writer)user
	rel := relative_path(root, path)
	has_non_root_user := false
	for line, index in strings.split_lines(text, context.temp_allocator) {
		trimmed := strings.trim_space(line)
		upper := strings.to_upper(trimmed, context.temp_allocator)
		if strings.has_prefix(upper, "FROM ") && !has_sha256_digest(trimmed) {
			finding(w, "high", "dockerfile", rel, index + 1, "FROM image is not pinned by sha256 digest")
		}
		if strings.has_prefix(upper, "USER ") {
			user := strings.to_lower(strings.trim_space(trimmed[len("USER "):]), context.temp_allocator)
			if user != "root" && user != "0" {
				has_non_root_user = true
			}
		}
		lower := strings.to_lower(trimmed, context.temp_allocator)
		if strings.contains(lower, "curl") && strings.contains(lower, "|") &&
		   (strings.contains(lower, "bash") || strings.contains(lower, " sh")) {
			finding(w, "warn", "dockerfile", rel, index + 1, "curl output is piped to a shell")
		}
	}
	if !has_non_root_user {
		finding(w, "warn", "dockerfile", rel, 0, "no non-root USER instruction found")
	}
}

has_sha256_digest :: proc(line: string) -> bool {
	marker := "@sha256:"
	index := strings.index(line, marker)
	if index < 0 {
		return false
	}
	digest := line[index + len(marker):]
	if len(digest) < 64 {
		return false
	}
	for c in digest[:64] {
		if !((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')) {
			return false
		}
	}
	if len(digest) > 64 {
		next := digest[64]
		return next == ' ' || next == '\t'
	}
	return true
}

audit_compose :: proc(workspace: string, allocator := context.allocator) -> string {
	w: Finding_Writer
	writer_init(&w, allocator)
	walk_files(workspace, workspace, &w, compose_visit, allocator)
	return writer_text(&w)
}

compose_visit :: proc(root, path: string, user: rawptr, allocator: runtime.Allocator) {
	name := strings.to_lower(filepath.base(path), context.temp_allocator)
	if name != "compose.yml" && name != "compose.yaml" &&
	   name != "docker-compose.yml" && name != "docker-compose.yaml" {
		return
	}
	text, ok := read_small_file(path, allocator)
	if !ok {
		return
	}
	defer delete(text)
	w := cast(^Finding_Writer)user
	rel := relative_path(root, path)
	for line, index in strings.split_lines(text, context.temp_allocator) {
		lower := strings.to_lower(strings.trim_space(line), context.temp_allocator)
		if strings.has_prefix(lower, "privileged:") && strings.contains(lower, "true") {
			finding(w, "warn", "compose", rel, index + 1, "privileged container enabled")
		}
		if strings.contains(lower, "/var/run/docker.sock") {
			finding(w, "warn", "compose", rel, index + 1, "Docker socket is mounted")
		}
	}
}
