// SPDX-License-Identifier: 0BSD
package secure

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "nullray:constants"

Scanner_Proc :: #type proc(workspace: string, allocator := context.allocator) -> string

Finding_Writer :: struct {
	builder:  strings.Builder,
	count:    int,
}

writer_init :: proc(w: ^Finding_Writer, allocator := context.allocator) {
	strings.builder_init(&w.builder, allocator)
}

finding :: proc(w: ^Finding_Writer, severity, scanner, path: string, line: int, reason: string) {
	if w.count > 0 {
		strings.write_string(&w.builder, "\n")
	}
	if line > 0 {
		fmt.sbprintf(&w.builder, "%s|%s|%s:%d|%s", severity, scanner, path, line, reason)
	} else {
		fmt.sbprintf(&w.builder, "%s|%s|%s|%s", severity, scanner, path, reason)
	}
	w.count += 1
}

writer_text :: proc(w: ^Finding_Writer) -> string {
	if w.count == 0 {
		strings.write_string(&w.builder, "none")
	}
	return strings.to_string(w.builder)
}

relative_path :: proc(root, path: string) -> string {
	if strings.has_prefix(path, root) {
		rel := path[len(root):]
		if len(rel) > 0 && rel[0] == filepath.SEPARATOR {
			return rel[1:]
		}
		if len(rel) > 0 {
			return rel
		}
	}
	return path
}

read_small_file :: proc(path: string, allocator := context.allocator) -> (string, bool) {
	data, err := os.read_entire_file(path, allocator)
	if err != nil {
		return "", false
	}
	if len(data) > constants.MAX_TOOL_FILE_BYTES {
		delete(data)
		return "", false
	}
	return string(data), true
}

walk_files :: proc(
	root, dir: string,
	user: rawptr,
	visit: #type proc(root, path: string, user: rawptr, allocator: runtime.Allocator),
	allocator: runtime.Allocator,
) {
	entries, err := os.read_all_directory_by_path(dir, context.temp_allocator)
	if err != nil {
		return
	}
	defer os.file_info_slice_delete(entries, context.temp_allocator)
	for entry in entries {
		if entry.name == ".git" || entry.name == "node_modules" || entry.name == "bin" || entry.name == ".cache" {
			continue
		}
		child, jerr := filepath.join({dir, entry.name}, context.temp_allocator)
		if jerr != nil {
			continue
		}
		if entry.type == .Directory {
			walk_files(root, child, user, visit, allocator)
		} else if entry.type == .Regular {
			visit(root, child, user, allocator)
		}
	}
}

has_high :: proc(text: string) -> bool {
	return strings.has_prefix(text, "high|") || strings.contains(text, "\nhigh|")
}

audit_all :: proc(workspace: string, allocator := context.allocator) -> string {
	scanners := []Scanner_Proc{
		audit_actions,
		audit_dockerfile,
		audit_compose,
		audit_owasp,
		audit_deps,
	}
	b: strings.Builder
	strings.builder_init(&b, allocator)
	wrote := false
	for scanner in scanners {
		text := scanner(workspace, allocator)
		if text == "none" {
			delete(text)
			continue
		}
		if wrote {
			strings.write_string(&b, "\n")
		}
		strings.write_string(&b, text)
		wrote = true
		delete(text)
	}
	if !wrote {
		strings.write_string(&b, "none")
	}
	return strings.to_string(b)
}
