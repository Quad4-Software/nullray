/*
Shared JSON arg parsing and path helpers for agent tools.
*/

package tools

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "nullray:sandbox"

SKIP_DIR_NAMES :: []string{".git", "node_modules", "bin", ".cache"}

json_arg_string :: proc(args_json: string, key: string, allocator := context.allocator) -> (value: string, err: string) {
	doc, parse_err := json.parse_string(args_json, .JSON, allocator = context.temp_allocator)
	if parse_err != nil {
		return "", fmt.aprintf("bad tool args JSON: %v", parse_err, allocator = allocator)
	}
	obj, obj_ok := doc.(json.Object)
	if !obj_ok {
		return "", strings.clone("tool args must be a JSON object", allocator)
	}
	val, found := obj[key]
	if !found {
		return "", fmt.aprintf("missing field: %s", key, allocator = allocator)
	}
	s, sok := val.(json.String)
	if !sok {
		return "", fmt.aprintf("field %s must be a string", key, allocator = allocator)
	}
	return strings.clone(string(s), allocator), ""
}

json_arg_string_optional :: proc(
	args_json: string,
	key: string,
	default: string,
	allocator := context.allocator,
) -> (value: string, err: string) {
	doc, parse_err := json.parse_string(args_json, .JSON, allocator = context.temp_allocator)
	if parse_err != nil {
		return "", fmt.aprintf("bad tool args JSON: %v", parse_err, allocator = allocator)
	}
	obj, obj_ok := doc.(json.Object)
	if !obj_ok {
		return "", strings.clone("tool args must be a JSON object", allocator)
	}
	val, found := obj[key]
	if !found {
		return strings.clone(default, allocator), ""
	}
	s, sok := val.(json.String)
	if !sok {
		return "", fmt.aprintf("field %s must be a string", key, allocator = allocator)
	}
	return strings.clone(string(s), allocator), ""
}

json_arg_bool_string :: proc(
	args_json: string,
	key: string,
	default: bool,
	allocator := context.allocator,
) -> (value: bool, err: string) {
	doc, parse_err := json.parse_string(args_json, .JSON, allocator = context.temp_allocator)
	if parse_err != nil {
		return default, fmt.aprintf("bad tool args JSON: %v", parse_err, allocator = allocator)
	}
	obj, obj_ok := doc.(json.Object)
	if !obj_ok {
		return default, strings.clone("tool args must be a JSON object", allocator)
	}
	val, found := obj[key]
	if !found {
		return default, ""
	}
	s, sok := val.(json.String)
	if !sok {
		return default, fmt.aprintf("field %s must be a string", key, allocator = allocator)
	}
	switch strings.to_lower(string(s), context.temp_allocator) {
	case "true", "1", "yes":
		return true, ""
	case "false", "0", "no":
		return false, ""
	}
	return default, fmt.aprintf("field %s must be \"true\" or \"false\"", key, allocator = allocator)
}

resolve_path :: proc(path: string, allocator := context.allocator) -> string {
	clean, cerr := filepath.clean(path, context.temp_allocator)
	if cerr != nil {
		clean = path
	}
	if filepath.is_abs(clean) {
		return strings.clone(clean, allocator)
	}
	workspace := workspace_root(context.temp_allocator)
	joined, jerr := filepath.join({workspace, clean}, allocator)
	if jerr != nil {
		return strings.clone(clean, allocator)
	}
	return joined
}

workspace_root :: proc(allocator := context.allocator) -> string {
	st := sandbox.state()
	if st != nil && len(st.workspace) > 0 {
		return strings.clone(st.workspace, allocator)
	}
	if cwd, wderr := os.get_working_directory(allocator); wderr == nil {
		return cwd
	}
	return strings.clone(".", allocator)
}

should_skip_dir :: proc(name: string) -> bool {
	for skip in SKIP_DIR_NAMES {
		if name == skip {
			return true
		}
	}
	return false
}

glob_suffix_match :: proc(pattern, filename: string) -> bool {
	p := pattern
	if idx := strings.index(p, "**/"); idx >= 0 {
		p = p[idx + 3:]
	}
	if strings.has_prefix(p, "*") {
		suffix := p[1:]
		return strings.has_suffix(filename, suffix)
	}
	return filename == p
}

glob_filter_match :: proc(glob, filename: string) -> bool {
	if len(glob) == 0 {
		return true
	}
	if strings.has_prefix(glob, "*") {
		suffix := glob[1:]
		return strings.has_suffix(filename, suffix)
	}
	return filename == glob
}

truncate_line :: proc(line: string, max: int) -> string {
	if len(line) <= max {
		return line
	}
	return line[:max]
}
