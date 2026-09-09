// SPDX-License-Identifier: 0BSD
package structure

import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "nullray:constants"

Policy :: struct {
	max_file_lines:  int,
	warn_file_lines: int,
}

default_policy :: proc() -> Policy {
	return {
		max_file_lines = constants.DEFAULT_MAX_FILE_LINES,
		warn_file_lines = constants.DEFAULT_WARN_FILE_LINES,
	}
}

load_policy :: proc(workspace: string, allocator := context.allocator) -> (Policy, string) {
	policy := default_policy()
	path, jerr := filepath.join({workspace, constants.POLICY_FILE}, context.temp_allocator)
	if jerr != nil {
		return policy, fmt.aprintf("policy path failed: %v", jerr, allocator = allocator)
	}
	data, rerr := os.read_entire_file(path, context.temp_allocator)
	if rerr != nil {
		return policy, ""
	}
	doc, perr := json.parse_string(string(data), .JSON, allocator = context.temp_allocator)
	if perr != nil {
		return policy, fmt.aprintf("invalid %s: %v", constants.POLICY_FILE, perr, allocator = allocator)
	}
	obj, ok := doc.(json.Object)
	if !ok {
		return policy, fmt.aprintf("%s must contain a JSON object", constants.POLICY_FILE, allocator = allocator)
	}
	if value, found := obj["max_file_lines"]; found {
		n, valid := policy_integer(value)
		if !valid || n < 1 {
			return policy, fmt.aprintf("%s max_file_lines must be a positive integer", constants.POLICY_FILE, allocator = allocator)
		}
		policy.max_file_lines = n
	}
	if value, found := obj["warn_lines"]; found {
		n, valid := policy_integer(value)
		if !valid || n < 1 {
			return policy, fmt.aprintf("%s warn_lines must be a positive integer", constants.POLICY_FILE, allocator = allocator)
		}
		policy.warn_file_lines = n
	}
	if policy.warn_file_lines > policy.max_file_lines {
		return default_policy(), fmt.aprintf("%s warn_lines cannot exceed max_file_lines", constants.POLICY_FILE, allocator = allocator)
	}
	return policy, ""
}

policy_integer :: proc(value: json.Value) -> (int, bool) {
	#partial switch v in value {
	case json.Integer:
		return int(v), true
	case json.Float:
		n := int(v)
		return n, f64(n) == f64(v)
	}
	return 0, false
}

line_count :: proc(text: string) -> int {
	if len(text) == 0 {
		return 0
	}
	count := 1
	for c in text {
		if c == '\n' {
			count += 1
		}
	}
	if text[len(text) - 1] == '\n' {
		count -= 1
	}
	return count
}

threshold :: proc(lines: int, policy: Policy) -> string {
	if lines > policy.max_file_lines {
		return "godfile"
	}
	if lines >= policy.warn_file_lines {
		return "warn"
	}
	return "ok"
}

enabled :: proc() -> bool {
	if value, ok := os.lookup_env(constants.ENV_STRUCTURE, context.temp_allocator); ok {
		switch strings.to_lower(strings.trim_space(value), context.temp_allocator) {
		case "0", "false", "off", "no", "disable":
			return false
		}
	}
	return true
}

growth_error :: proc(
	workspace, path, old_text, new_text: string,
	allow_godfile: bool,
	allocator := context.allocator,
) -> string {
	if allow_godfile || !enabled() {
		return ""
	}
	policy, _ := load_policy(workspace, context.temp_allocator)
	old_lines := line_count(old_text)
	new_lines := line_count(new_text)
	if new_lines > policy.max_file_lines && new_lines > old_lines {
		return fmt.aprintf(
			"structure gate blocked %s: lines=%d max=%d, pass allow_godfile=true to override",
			path,
			new_lines,
			policy.max_file_lines,
			allocator = allocator,
		)
	}
	return ""
}

// Audit Odin sources under workspace. Skips vendor and build trees.
// Report lines look like godfile|path|lines=N max=M or warn|... or none.
audit :: proc(workspace: string, allocator := context.allocator) -> (string, string) {
	policy, perr := load_policy(workspace, allocator)
	if len(perr) > 0 {
		return "", perr
	}
	b: strings.Builder
	strings.builder_init(&b, allocator)
	findings := 0
	audit_walk(workspace, workspace, policy, &b, &findings, allocator)
	if findings == 0 {
		strings.write_string(&b, "none")
	}
	return strings.to_string(b), ""
}

report_has_godfiles :: proc(report: string) -> bool {
	if len(report) == 0 || report == "none" {
		return false
	}
	start := 0
	for i := 0; i <= len(report); i += 1 {
		if i < len(report) && report[i] != '\n' {
			continue
		}
		line := report[start:i]
		if strings.has_prefix(line, "godfile|") {
			return true
		}
		start = i + 1
	}
	return false
}

audit_skip_dir :: proc(name: string) -> bool {
	switch name {
	case ".git", "node_modules", "bin", ".cache", "vendor", ".tmp", "coverage", "dist":
		return true
	}
	return false
}

audit_is_source :: proc(name: string) -> bool {
	return strings.has_suffix(strings.to_lower(name, context.temp_allocator), ".odin")
}

audit_walk :: proc(
	root, dir: string,
	policy: Policy,
	b: ^strings.Builder,
	findings: ^int,
	allocator: runtime.Allocator,
) {
	entries, err := os.read_all_directory_by_path(dir, context.temp_allocator)
	if err != nil {
		return
	}
	defer os.file_info_slice_delete(entries, context.temp_allocator)
	for entry in entries {
		if audit_skip_dir(entry.name) {
			continue
		}
		child, jerr := filepath.join({dir, entry.name}, context.temp_allocator)
		if jerr != nil {
			continue
		}
		if entry.type == .Directory {
			audit_walk(root, child, policy, b, findings, allocator)
			continue
		}
		if entry.type != .Regular || !audit_is_source(entry.name) {
			continue
		}
		data, rerr := os.read_entire_file(child, context.temp_allocator)
		if rerr != nil || len(data) > constants.MAX_TOOL_FILE_BYTES {
			continue
		}
		lines := line_count(string(data))
		level := threshold(lines, policy)
		if level == "ok" {
			continue
		}
		rel := relative_path(root, child)
		if findings^ > 0 {
			strings.write_string(b, "\n")
		}
		fmt.sbprintf(b, "%s|%s|lines=%d max=%d", level, rel, lines, policy.max_file_lines)
		findings^ += 1
	}
}

find_repo_root :: proc(allocator := context.allocator) -> string {
	cwd, cerr := os.get_working_directory(context.temp_allocator)
	if cerr != nil {
		return ""
	}
	dir := cwd
	for {
		marker, jerr := filepath.join({dir, "nullray", "structure", "structure.odin"}, context.temp_allocator)
		if jerr == nil && os.exists(marker) {
			return strings.clone(dir, allocator)
		}
		parent := filepath.dir(dir)
		if parent == dir || len(parent) == 0 {
			break
		}
		dir = parent
	}
	return ""
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
