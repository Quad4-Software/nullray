// SPDX-License-Identifier: 0BSD
/*
repo_map tool: shallow workspace tree for orientation.
*/

package tools

import "base:runtime"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "nullray:constants"
import "nullray:sandbox"

REPO_MAP_SKIP :: []string{".git", "node_modules", "bin", ".cache", "vendor", ".nullray"}

tool_repo_map :: proc(args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	path, perr := json_arg_string_optional(args_json, "path", ".", allocator)
	if perr != "" {
		return "", perr
	}
	defer delete(path)
	depth, derr := json_arg_int_optional(args_json, "depth", constants.DEFAULT_REPO_MAP_DEPTH, allocator)
	if derr != "" {
		return "", derr
	}
	if depth < 0 {
		depth = 0
	}
	if depth > constants.MAX_REPO_MAP_DEPTH {
		depth = constants.MAX_REPO_MAP_DEPTH
	}
	focus, ferr := json_arg_string_optional(args_json, "focus", "", allocator)
	if ferr != "" {
		return "", ferr
	}
	defer delete(focus)

	abs := resolve_path(path, allocator)
	defer delete(abs)
	if !sandbox.path_allowed(sandbox.state(), abs, false) {
		return "", strings.clone("path not allowed for read", allocator)
	}

	b: strings.Builder
	strings.builder_init(&b, allocator)
	budget := constants.MAX_REPO_MAP_BYTES
	truncated := false
	repo_map_walk(abs, abs, 0, depth, focus, &b, &budget, &truncated, allocator)
	if truncated {
		strings.write_string(&b, "\n... truncated ...\n")
	}
	return strings.to_string(b), ""
}

@(private)
repo_map_should_skip :: proc(name: string) -> bool {
	for s in REPO_MAP_SKIP {
		if name == s {
			return true
		}
	}
	return should_skip_dir(name)
}

@(private)
repo_map_walk :: proc(
	root, dir: string,
	depth, max_depth: int,
	focus: string,
	b: ^strings.Builder,
	budget: ^int,
	truncated: ^bool,
	allocator: runtime.Allocator,
) {
	if truncated^ || budget^ <= 0 {
		truncated^ = true
		return
	}
	entries, lerr := os.read_all_directory_by_path(dir, context.temp_allocator)
	if lerr != nil {
		return
	}
	defer os.file_info_slice_delete(entries, context.temp_allocator)

	for e in entries {
		if truncated^ || budget^ <= 0 {
			truncated^ = true
			return
		}
		if e.type == .Directory && repo_map_should_skip(e.name) {
			continue
		}
		child, jerr := filepath.join({dir, e.name}, context.temp_allocator)
		if jerr != nil {
			continue
		}
		if !sandbox.path_allowed(sandbox.state(), child, false) {
			continue
		}
		if len(focus) > 0 && e.type != .Directory {
			if !glob_suffix_match(focus, e.name) && !strings.contains(e.name, focus) {
				continue
			}
		}
		rel := child
		if strings.has_prefix(child, root) {
			trim := child[len(root):]
			if len(trim) > 0 && (trim[0] == '/' || trim[0] == '\\') {
				trim = trim[1:]
			}
			if len(trim) > 0 {
				rel = trim
			} else {
				rel = e.name
			}
		}
		indent := depth
		line_b: strings.Builder
		strings.builder_init(&line_b, context.temp_allocator)
		for _ in 0 ..< indent {
			strings.write_string(&line_b, "  ")
		}
		strings.write_string(&line_b, e.name)
		if e.type == .Directory {
			strings.write_byte(&line_b, '/')
		}
		strings.write_byte(&line_b, '\n')
		line := strings.to_string(line_b)
		if len(line) > budget^ {
			truncated^ = true
			return
		}
		strings.write_string(b, line)
		budget^ -= len(line)
		_ = rel
		if e.type == .Directory && depth < max_depth {
			repo_map_walk(root, child, depth + 1, max_depth, focus, b, budget, truncated, allocator)
		}
	}
}
