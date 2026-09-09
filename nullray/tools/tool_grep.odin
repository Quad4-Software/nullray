// SPDX-License-Identifier: 0BSD
/*
grep_files: substring or regex search. Prefers ripgrep when present.
*/

package tools

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:text/regex"
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
	case_i, cerr := json_arg_bool_string(args_json, "case_insensitive", false, allocator)
	if cerr != "" {
		return "", cerr
	}
	use_regex, rerr := json_arg_bool_string(args_json, "regex", false, allocator)
	if rerr != "" {
		return "", rerr
	}
	engine, eerr := json_arg_string_optional(args_json, "engine", "auto", allocator)
	if eerr != "" {
		return "", eerr
	}
	defer delete(engine)

	abs := resolve_path(search_path, allocator)
	defer delete(abs)
	if !sandbox.path_allowed(sandbox.state(), abs, false) {
		return "", strings.clone("path not allowed for read", allocator)
	}

	eng := strings.to_lower(strings.trim_space(engine), context.temp_allocator)
	prefer_rg := eng == "auto" || eng == "rg" || eng == "ripgrep"
	force_builtin := eng == "builtin" || eng == "internal"
	if prefer_rg && !force_builtin {
		if out, ok := grep_via_rg(abs, pattern, glob, case_i, use_regex, allocator); ok {
			return out, ""
		}
		if eng == "rg" || eng == "ripgrep" {
			return "", strings.clone("ripgrep (rg) not found on PATH", allocator)
		}
	}
	return grep_builtin(abs, pattern, glob, case_i, use_regex, allocator)
}

@(private)
grep_via_rg :: proc(
	abs, pattern, glob: string,
	case_i, use_regex: bool,
	allocator: runtime.Allocator,
) -> (result: string, ok: bool) {
	exe, found := find_on_path("rg", context.temp_allocator)
	if !found {
		return "", false
	}
	argv: [dynamic]string
	argv.allocator = context.temp_allocator
	append(&argv, exe, "--no-heading", "--line-number", "--color", "never")
	append(&argv, "-m", fmt.tprintf("%d", MAX_GREP_MATCHES))
	append(&argv, "-g", "!.git/**", "-g", "!node_modules/**", "-g", "!bin/**", "-g", "!.cache/**", "-g", "!vendor/**")
	if case_i {
		append(&argv, "-i")
	}
	if !use_regex {
		append(&argv, "-F")
	}
	if len(glob) > 0 {
		append(&argv, "-g", glob)
	}
	append(&argv, "--", pattern, abs)
	out, err := run_capture_argv(argv[:], allocator)
	if err != "" {
		// No matches often exits 1 with empty stdout.
		if len(strings.trim_space(out)) == 0 {
			delete(out)
			return strings.clone("", allocator), true
		}
		delete(out)
		return "", false
	}
	return grep_normalize_rg_output(out, abs, allocator), true
}

@(private)
grep_normalize_rg_output :: proc(owned: string, abs: string, allocator: runtime.Allocator) -> string {
	ws := workspace_root(context.temp_allocator)
	b: strings.Builder
	strings.builder_init(&b, allocator)
	first := true
	for line in strings.split_lines(owned, context.temp_allocator) {
		if len(line) == 0 {
			continue
		}
		rel := line
		if len(ws) > 0 && strings.has_prefix(line, ws) {
			trim := line[len(ws):]
			if len(trim) > 0 && trim[0] == filepath.SEPARATOR {
				trim = trim[1:]
			}
			if len(trim) > 0 {
				rel = trim
			}
		} else if strings.has_prefix(line, abs) {
			trim := line[len(abs):]
			if len(trim) > 0 && trim[0] == filepath.SEPARATOR {
				trim = trim[1:]
			}
			if len(trim) > 0 {
				rel = trim
			}
		}
		// Truncate display line after path:line:
		col2 := -1
		colon_count := 0
		for i in 0 ..< len(rel) {
			if rel[i] == ':' {
				colon_count += 1
				if colon_count == 2 {
					col2 = i
					break
				}
			}
		}
		if col2 >= 0 && col2 + 1 < len(rel) {
			prefix := rel[:col2 + 1]
			text := truncate_line(rel[col2 + 1:], MAX_GREP_LINE_CHARS)
			rel = fmt.tprintf("%s%s", prefix, text)
		}
		if !first {
			strings.write_string(&b, "\n")
		}
		first = false
		strings.write_string(&b, rel)
	}
	delete(owned)
	return strings.to_string(b)
}

@(private)
grep_builtin :: proc(
	abs, pattern, glob: string,
	case_i, use_regex: bool,
	allocator: runtime.Allocator,
) -> (result: string, err: string) {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	match_count := 0
	file_count := 0
	re: regex.Regular_Expression
	has_re := false
	if use_regex {
		flags: regex.Flags = {.No_Capture}
		if case_i {
			flags += {.Case_Insensitive}
		}
		compiled, cerr := regex.create(pattern, flags)
		if cerr != nil {
			return "", fmt.aprintf("invalid regex: %v", cerr, allocator = allocator)
		}
		re = compiled
		has_re = true
	}
	defer if has_re {
		regex.destroy(re)
	}
	needle := pattern
	needle_owned: string
	if !use_regex && case_i {
		needle_owned = strings.to_lower(pattern, allocator)
		needle = needle_owned
	}
	defer if len(needle_owned) > 0 {
		delete(needle_owned)
	}
	grep_err := grep_walk(abs, needle, glob, case_i, use_regex, has_re, re, &b, &match_count, &file_count, allocator)
	if grep_err != "" {
		return "", grep_err
	}
	return strings.to_string(b), ""
}

@(private)
grep_line_match :: proc(
	line, needle: string,
	case_i, use_regex, has_re: bool,
	re: regex.Regular_Expression,
) -> bool {
	if use_regex && has_re {
		_, ok := regex.match_and_allocate_capture(re, line, context.temp_allocator, context.temp_allocator)
		return ok
	}
	if case_i {
		lower := strings.to_lower(line, context.temp_allocator)
		return strings.contains(lower, needle)
	}
	return strings.contains(line, needle)
}

@(private)
grep_walk :: proc(
	dir: string,
	pattern: string,
	glob: string,
	case_i: bool,
	use_regex: bool,
	has_re: bool,
	re: regex.Regular_Expression,
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
		for line, li in strings.split_lines(text, context.temp_allocator) {
			if match_count^ >= MAX_GREP_MATCHES {
				return ""
			}
			if !grep_line_match(line, pattern, case_i, use_regex, has_re, re) {
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
			line_no := li + 1
			strings.write_string(b, rel)
			strings.write_string(b, ":")
			fmt.sbprintf(b, "%d:", line_no)
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
			if err := grep_walk(child, pattern, glob, case_i, use_regex, has_re, re, b, match_count, file_count, allocator); err != "" {
				return err
			}
			continue
		}
		if e.type == .Regular {
			if err := grep_walk(child, pattern, glob, case_i, use_regex, has_re, re, b, match_count, file_count, allocator); err != "" {
				return err
			}
		}
	}
	return ""
}
