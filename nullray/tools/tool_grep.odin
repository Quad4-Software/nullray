/*
grep_files tool: recursive substring search under sandbox.
*/

package tools

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "nullray:constants"
import "nullray:sandbox"

MAX_GREP_MATCHES :: 200
MAX_GREP_LINE_CHARS :: 80
MAX_GREP_FILES :: 2000

tool_grep_files :: proc(args_json: string, allocator := context.allocator) -> (result: string, err: string) {
	pattern, perr := json_arg_string(args_json, "pattern", allocator)
	if perr != "" {
		return "", perr
	}
	defer delete(pattern)
	search_path, serr := json_arg_string_optional(args_json, "path", ".", allocator)
	if serr != "" {
		return "", serr
	}
	defer delete(search_path)
	glob, gerr := json_arg_string_optional(args_json, "glob", "", allocator)
	if gerr != "" {
		return "", gerr
	}
	defer delete(glob)

	abs := resolve_path(search_path, allocator)
	defer delete(abs)
	if !sandbox.path_allowed(sandbox.state(), abs, false) {
		return "", strings.clone("path not allowed for read", allocator)
	}

	b: strings.Builder
	strings.builder_init(&b, allocator)
	match_count := 0
	file_count := 0
	grep_err := grep_walk(abs, pattern, glob, &b, &match_count, &file_count, allocator)
	if grep_err != "" {
		return "", grep_err
	}
	return strings.to_string(b), ""
}

@(private)
grep_walk :: proc(
	dir: string,
	pattern: string,
	glob: string,
	b: ^strings.Builder,
	match_count: ^int,
	file_count: ^int,
	allocator: runtime.Allocator,
) -> string {
	if file_count^ >= MAX_GREP_FILES {
		return ""
	}

	info, stat_err := os.stat(dir, context.temp_allocator)
	if stat_err != nil {
		return ""
	}
	if info.type != .Regular && info.type != .Directory {
		return ""
	}
	if info.type == .Regular {
		file_count^ += 1
		if file_count^ > MAX_GREP_FILES {
			return ""
		}
		name := filepath.base(dir)
		if len(glob) > 0 && !glob_filter_match(glob, name) {
			return ""
		}
		if len(dir) > 0 && !sandbox.path_allowed(sandbox.state(), dir, false) {
			return ""
		}
		data, read_err := os.read_entire_file(dir, allocator)
		if read_err != nil {
			return ""
		}
		defer delete(data)
		if len(data) > constants.MAX_TOOL_FILE_BYTES {
			return ""
		}
		text := string(data)
		for line in strings.split_lines(text, context.temp_allocator) {
			if match_count^ >= MAX_GREP_MATCHES {
				return ""
			}
			if !strings.contains(line, pattern) {
				continue
			}
			if match_count^ > 0 {
				strings.write_string(b, "\n")
			}
			rel := dir
			if ws := workspace_root(context.temp_allocator); len(ws) > 0 && strings.has_prefix(dir, ws) {
				trim := dir[len(ws):]
				if len(trim) > 0 && trim[0] == filepath.SEPARATOR {
					trim = trim[1:]
				}
				if len(trim) > 0 {
					rel = trim
				}
			}
			strings.write_string(b, rel)
			strings.write_string(b, ":")
			strings.write_string(b, truncate_line(line, MAX_GREP_LINE_CHARS))
			match_count^ += 1
		}
		return ""
	}

	entries, lerr := os.read_all_directory_by_path(dir, context.temp_allocator)
	if lerr != nil {
		return ""
	}
	defer os.file_info_slice_delete(entries, context.temp_allocator)

	for e in entries {
		if match_count^ >= MAX_GREP_MATCHES || file_count^ >= MAX_GREP_FILES {
			return ""
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
			if err := grep_walk(child, pattern, glob, b, match_count, file_count, allocator); err != "" {
				return err
			}
			continue
		}
		if e.type == .Regular {
			if err := grep_walk(child, pattern, glob, b, match_count, file_count, allocator); err != "" {
				return err
			}
		}
	}
	return ""
}
