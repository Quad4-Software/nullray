// SPDX-License-Identifier: 0BSD
/*
Short status lines for live tool activity in the TUI.
*/

package tools

import "core:fmt"
import "core:strings"

TOOL_ACTIVITY_DETAIL_MAX :: 72

@(private)
truncate_activity :: proc(s: string, max: int) -> string {
	if max <= 0 || len(s) <= max {
		return s
	}
	if max <= 1 {
		return s[:max]
	}
	return fmt.tprintf("%s…", s[:max - 1])
}

@(private)
activity_field :: proc(args_json, key: string) -> string {
	v, err := json_arg_string_optional(args_json, key, "", context.temp_allocator)
	if len(err) > 0 || len(v) == 0 {
		return ""
	}
	return v
}

/*
Build a one-line "running <tool>: <detail>" string for status and transcript.
*/
tool_activity_line :: proc(name, args_json: string, allocator := context.allocator) -> string {
	detail := ""
	switch name {
	case "run_shell", "verify":
		detail = activity_field(args_json, "command")
	case "read_file", "write_file", "edit_file", "list_dir":
		detail = activity_field(args_json, "path")
	case "grep_files":
		detail = activity_field(args_json, "pattern")
		if path := activity_field(args_json, "path"); len(path) > 0 && path != "." {
			detail = fmt.tprintf("%s in %s", detail, path)
		}
	case "glob_files":
		detail = activity_field(args_json, "pattern")
	case "run_script":
		detail = activity_field(args_json, "language")
	case "load_skill":
		detail = activity_field(args_json, "id")
	case "apply_edits":
		detail = "edits"
	case "list_skills", "compact_context":
		detail = ""
	case:
		if path := activity_field(args_json, "path"); len(path) > 0 {
			detail = path
		} else if cmd := activity_field(args_json, "command"); len(cmd) > 0 {
			detail = cmd
		}
	}
	detail = truncate_activity(strings.trim_space(detail), TOOL_ACTIVITY_DETAIL_MAX)
	tool_name := name
	if len(tool_name) == 0 {
		tool_name = "tool"
	}
	if len(detail) > 0 {
		return fmt.aprintf("running %s: %s", tool_name, detail, allocator = allocator)
	}
	return fmt.aprintf("running %s", tool_name, allocator = allocator)
}
