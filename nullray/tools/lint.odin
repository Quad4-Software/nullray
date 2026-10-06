// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Post-edit lint. Optional .nullray/lint.json or config lint.json maps globs
to a shell command. After a successful write the matching command runs and
its output is returned for the is_error channel. NULLRAY_LINT=0 disables.
*/

package tools

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "nullray:constants"
import "nullray:sandbox"

Lint_Rule :: struct {
	glob: string,
	cmd:  string,
}

lint_enabled :: proc() -> bool {
	if v, ok := os.lookup_env(constants.ENV_LINT, context.temp_allocator); ok {
		switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
		case "0", "false", "off", "no", "disable":
			return false
		}
	}
	return true
}

lint_load_rules :: proc(allocator := context.temp_allocator) -> []Lint_Rule {
	if !lint_enabled() {
		return nil
	}
	out := make([dynamic]Lint_Rule, allocator)
	ws := workspace_root(context.temp_allocator)
	if len(ws) > 0 {
		p, _ := filepath.join({ws, ".nullray", constants.LINT_FILE}, context.temp_allocator)
		lint_load_file(&out, p, allocator)
	}
	cfg := sandbox.resolve_config_dir(context.temp_allocator)
	if len(cfg) > 0 {
		p, _ := filepath.join({cfg, constants.LINT_FILE}, context.temp_allocator)
		lint_load_file(&out, p, allocator)
	}
	return out[:]
}

@(private)
lint_load_file :: proc(out: ^[dynamic]Lint_Rule, path: string, allocator := context.temp_allocator) {
	data, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil || len(data) == 0 {
		return
	}
	doc, perr := json.parse_string(string(data), .JSON, allocator = context.temp_allocator)
	if perr != nil {
		return
	}
	root, ok := doc.(json.Object)
	if !ok {
		return
	}
	arr, aok := root["rules"].(json.Array)
	if !aok {
		return
	}
	for item in arr {
		obj, ook := item.(json.Object)
		if !ook {
			continue
		}
		glob, cmd := "", ""
		if v, vok := obj["glob"].(json.String); vok {
			glob = strings.trim_space(string(v))
		}
		if v, vok := obj["cmd"].(json.String); vok {
			cmd = strings.trim_space(string(v))
		}
		if len(glob) == 0 || len(cmd) == 0 {
			continue
		}
		append(out, Lint_Rule{glob = glob, cmd = cmd})
	}
}

lint_rule_for_path :: proc(path: string, rules: []Lint_Rule) -> (Lint_Rule, bool) {
	base := path
	if i := strings.last_index_any(path, "/\\"); i >= 0 {
		base = path[i + 1:]
	}
	for r in rules {
		if glob_filter_match(r.glob, base) || glob_suffix_match(r.glob, base) {
			return r, true
		}
		if matched, err := os.match(r.glob, path); err == nil && matched {
			return r, true
		}
		if matched, err := os.match(r.glob, base); err == nil && matched {
			return r, true
		}
	}
	return {}, false
}

@(private)
lint_quote_path :: proc(path: string, allocator := context.temp_allocator) -> string {
	if strings.contains(path, "'") {
		esc, _ := strings.replace_all(path, "'", `'"'"'`, allocator)
		return fmt.tprintf("'%s'", esc)
	}
	return fmt.tprintf("'%s'", path)
}

lint_expand_cmd :: proc(cmd, path: string, allocator := context.temp_allocator) -> string {
	q := lint_quote_path(path, allocator)
	out := cmd
	if strings.contains(out, "{path}") {
		out, _ = strings.replace_all(out, "{path}", q, allocator)
	}
	if strings.contains(out, "{file}") {
		out, _ = strings.replace_all(out, "{file}", q, allocator)
	}
	return out
}

lint_looks_like_error :: proc(out: string) -> bool {
	low := strings.to_lower(out, context.temp_allocator)
	if strings.contains(low, "error:") || strings.contains(low, "error ") {
		return true
	}
	if strings.contains(low, "failed") && strings.contains(out, ":") {
		return true
	}
	return false
}

LINT_TIMEOUT_MS :: 15_000

lint_after_write :: proc(path: string, allocator := context.allocator) -> string {
	if len(path) == 0 || !lint_enabled() {
		return ""
	}
	rules := lint_load_rules()
	rule, ok := lint_rule_for_path(path, rules)
	if !ok {
		return ""
	}
	cmd := lint_expand_cmd(rule.cmd, path)
	ws := workspace_root(context.temp_allocator)
	argv: [3]string
	when ODIN_OS == .Windows {
		argv = {"cmd.exe", "/C", cmd}
	} else {
		argv = {"/bin/sh", "-c", cmd}
	}
	out, err := run_process_capture(argv[:], ws, LINT_TIMEOUT_MS, allocator)
	if len(err) > 0 && len(out) == 0 {
		return err
	}
	combined := out
	if len(err) > 0 {
		combined = fmt.aprintf("%s\n%s", out, err, allocator = allocator)
		delete(out)
		delete(err)
	}
	if !lint_looks_like_error(combined) {
		delete(combined)
		return ""
	}
	return combined
}
