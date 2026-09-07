// SPDX-License-Identifier: 0BSD
/*
glob_files tool: recursive filename pattern listing under sandbox.
*/

package tools

import "base:runtime"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "nullray:sandbox"

MAX_GLOB_RESULTS :: 500

tool_glob_files :: proc(args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	pattern, perr := json_arg_string(args_json, "pattern", allocator)
	if perr != "" {
		return "", perr
	}
	defer delete(pattern)

	root := workspace_root(allocator)
	defer delete(root)
	if !sandbox.path_allowed(sandbox.state(), root, false) {
		return "", strings.clone("workspace path not allowed for read", allocator)
	}

	b: strings.Builder
	strings.builder_init(&b, allocator)
	result_count := 0
	glob_walk(root, root, pattern, &b, &result_count, allocator)
	return strings.to_string(b), ""
}

@(private)
glob_walk :: proc(
	root, dir, pattern: string,
	b: ^strings.Builder,
	result_count: ^int,
	allocator: runtime.Allocator,
) {
	if result_count^ >= MAX_GLOB_RESULTS {
		return
	}

	entries, lerr := os.read_all_directory_by_path(dir, context.temp_allocator)
	if lerr != nil {
		return
	}
	defer os.file_info_slice_delete(entries, context.temp_allocator)

	for e in entries {
		if result_count^ >= MAX_GLOB_RESULTS {
			return
		}
		child, jerr := filepath.join({dir, e.name}, context.temp_allocator)
		if jerr != nil {
			continue
		}
		if e.type == .Directory {
			if should_skip_dir(e.name) {
				continue
			}
			if !sandbox.path_allowed(sandbox.state(), child, false) {
				continue
			}
			glob_walk(root, child, pattern, b, result_count, allocator)
			continue
		}
		if e.type != .Regular {
			continue
		}
		if !sandbox.path_allowed(sandbox.state(), child, false) {
			continue
		}
		if !glob_suffix_match(pattern, e.name) {
			continue
		}
		if result_count^ > 0 {
			strings.write_string(b, "\n")
		}
		rel := child
		if len(root) > 0 && strings.has_prefix(child, root) {
			trim := child[len(root):]
			if len(trim) > 0 && trim[0] == filepath.SEPARATOR {
				trim = trim[1:]
			}
			if len(trim) > 0 {
				rel = strings.clone(trim, allocator)
			}
		}
		strings.write_string(b, rel)
		result_count^ += 1
	}
}
