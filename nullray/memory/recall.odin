// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Scoped memory recall. Entries whose keys carry a trigger are injected at the
moment the matching tool runs, which is where lessons earn their keep.

Key conventions inside .nullray/memory:

  recall.path.<glob>    match the tool's path arg (edit_file, write_file,
                        read_file, multi_edit, patch). `**` crosses
                        separators, single `*` does not. Patterns without a
                        slash also match the basename.
  recall.cmd.<substr>   substring match on the run_shell command
  recall.tool.<name>    fires whenever that tool runs

Values stay short imperative lessons. Cap: RECALL_MAX_HITS entries,
RECALL_MAX_CHARS total. NULLRAY_RECALL=0 disables.
*/

package memory

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"

RECALL_MAX_HITS :: 5
RECALL_MAX_CHARS :: 1200
RECALL_VALUE_CHARS :: 240

// Returns a "<memory>...</memory>" block for the tool result, or "".
recall_for_tool :: proc(tool_name, args_json: string, allocator := context.allocator) -> string {
	if !recall_enabled() {
		return strings.clone("", allocator)
	}
	path_arg, cmd_arg := recall_extract_args(args_json)
	entries := load_entries(context.temp_allocator)
	defer destroy_entries(&entries, context.temp_allocator)

	out: strings.Builder
	strings.builder_init(&out, allocator)
	hits := 0
	for e in entries {
		if hits >= RECALL_MAX_HITS {
			break
		}
		if !strings.has_prefix(e.key, "recall.") {
			continue
		}
		if !recall_key_matches(e.key, tool_name, path_arg, cmd_arg) {
			continue
		}
		lesson := one_line_summary(e.value, RECALL_VALUE_CHARS, context.temp_allocator)
		if strings.builder_len(out) + len(lesson) + 8 > RECALL_MAX_CHARS {
			break
		}
		fmt.sbprintf(&out, "- %s\n", lesson)
		hits += 1
		if v, ok := os.lookup_env("NULLRAY_DEBUG", context.temp_allocator); ok && len(v) > 0 {
			fmt.eprintf("recall: %s matched %s\n", e.key, tool_name)
		}
	}
	if hits == 0 {
		strings.builder_destroy(&out)
		return strings.clone("", allocator)
	}
	body := strings.to_string(out)
	defer delete(body, allocator)
	return strings.concatenate({"<memory>\n", body, "</memory>\n"}, allocator)
}

recall_enabled :: proc() -> bool {
	if v, ok := os.lookup_env("NULLRAY_RECALL", context.temp_allocator); ok {
		low := strings.to_lower(strings.trim_space(v), context.temp_allocator)
		return low != "0" && low != "off" && low != "false" && low != "no"
	}
	return true
}

// Pull the path and command strings out of a tool arguments JSON object.
@(private)
recall_extract_args :: proc(args_json: string) -> (path_arg, cmd_arg: string) {
	if len(args_json) == 0 {
		return "", ""
	}
	v, err := json.parse_string(args_json, .JSON, allocator = context.temp_allocator)
	if err != .None {
		return "", ""
	}
	obj, ok := v.(json.Object)
	if !ok {
		return "", ""
	}
	path_keys := [4]string{"path", "file", "file_path", "target"}
	for key in path_keys {
		if pv, pok := obj[key]; pok {
			if s, is_str := pv.(json.String); is_str {
				path_arg = s
				break
			}
		}
	}
	if cv, cok := obj["command"]; cok {
		if s, is_str := cv.(json.String); is_str {
			cmd_arg = s
		}
	}
	return path_arg, cmd_arg
}

@(private)
recall_key_matches :: proc(key, tool_name, path_arg, cmd_arg: string) -> bool {
	if strings.has_prefix(key, "recall.path.") {
		pat := key[len("recall.path."):]
		if len(path_arg) > 0 && recall_glob_match(pat, path_arg) {
			return true
		}
		// Files also get written through run_shell heredocs and sed; match
		// path-like tokens in the command so those lessons still fire.
		if len(cmd_arg) > 0 {
			flat, _ := strings.replace_all(cmd_arg, "\t", " ", context.temp_allocator)
			for tok in strings.split(flat, " ", context.temp_allocator) {
				clean := strings.trim_left(tok, ">\"'(")
				clean = strings.trim_right(clean, "\"');&|")
				if len(clean) > 0 && recall_glob_match(pat, clean) {
					return true
				}
			}
		}
		return false
	}
	if strings.has_prefix(key, "recall.cmd.") {
		return len(cmd_arg) > 0 && strings.contains(cmd_arg, key[len("recall.cmd."):])
	}
	if strings.has_prefix(key, "recall.tool.") {
		return key[len("recall.tool."):] == tool_name
	}
	return false
}

// Glob with `**` crossing separators. A slash-free pattern also matches the
// basename, so `recall.path.Makefile` fires on any Makefile.
@(private)
recall_glob_match :: proc(pattern, path: string) -> bool {
	if len(pattern) == 0 {
		return false
	}
	if strings.contains(pattern, "**") {
		parts := strings.split(pattern, "**", context.temp_allocator)
		pos := 0
		for part, i in parts {
			if len(part) == 0 {
				continue
			}
			idx := strings.index(path[pos:], part)
			if idx < 0 {
				return false
			}
			pos += idx + len(part)
			_ = i
		}
		// A trailing ** accepts any suffix; a trailing literal must reach the end.
		last := parts[len(parts) - 1]
		if len(last) > 0 && !strings.has_suffix(pattern, "**") && !strings.has_suffix(path, last) {
			return false
		}
		return true
	}
	if matched, err := os.match(pattern, path); err == nil && matched {
		return true
	}
	if !strings.contains(pattern, "/") {
		base := path
		if idx := strings.last_index(path, "/"); idx >= 0 {
			base = path[idx + 1:]
		}
		if matched, err := os.match(pattern, base); err == nil && matched {
			return true
		}
	}
	return false
}
