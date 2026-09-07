// SPDX-License-Identifier: 0BSD
/*
Plan artifact paths and FINDINGS trailer parsing for review mode.
*/

package agent

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:strings"
import "core:time"
import "nullray:constants"
import "nullray:sandbox"

plan_out_from_env :: proc(allocator := context.allocator) -> string {
	if v, ok := os.lookup_env(constants.ENV_PLAN_OUT, context.temp_allocator); ok && len(v) > 0 {
		return strings.clone(v, allocator)
	}
	return ""
}

out_path_from_env :: proc(allocator := context.allocator) -> string {
	if v, ok := os.lookup_env(constants.ENV_OUT, context.temp_allocator); ok && len(v) > 0 {
		return strings.clone(v, allocator)
	}
	return ""
}

/*
Resolve where to write a plan.md body.
Priority: plan_out, then out_path when mode is plan, else workspace/.nullray/plans/stamp.md.
*/
resolve_plan_path :: proc(
	plan_out: string,
	out_path: string,
	workspace: string,
	allocator := context.allocator,
) -> string {
	if len(plan_out) > 0 {
		return strings.clone(plan_out, allocator)
	}
	if len(out_path) > 0 {
		return strings.clone(out_path, allocator)
	}
	ws := workspace
	if len(ws) == 0 {
		if st := sandbox.state(); st != nil && len(st.workspace) > 0 {
			ws = st.workspace
		} else if cwd, err := os.get_working_directory(context.temp_allocator); err == nil {
			ws = cwd
		} else {
			ws = "."
		}
	}
	name := fmt.tprintf("%d.md", time.to_unix_seconds(time.now()))
	dir, jerr := filepath.join({ws, constants.PLANS_DIR}, context.temp_allocator)
	if jerr != nil {
		return strings.clone(name, allocator)
	}
	path, perr := filepath.join({dir, name}, allocator)
	if perr != nil {
		return strings.clone(name, allocator)
	}
	return path
}

ensure_parent_dirs :: proc(path: string) -> string {
	dir := filepath.dir(path)
	if len(dir) == 0 || dir == "." {
		return ""
	}
	if err := os.make_directory_all(dir); err != nil && err != .Exist {
		return fmt.tprintf("mkdir %s: %v", dir, err)
	}
	return ""
}

/*
Write plan markdown to disk. Caller owns returned path string.
*/
save_plan_artifact :: proc(
	body: string,
	plan_out := "",
	out_path := "",
	workspace := "",
	allocator := context.allocator,
) -> (path: string, err: string) {
	trimmed := strings.trim_space(body)
	if len(trimmed) == 0 {
		return "", strings.clone("empty plan body", allocator)
	}
	path = resolve_plan_path(plan_out, out_path, workspace, allocator)
	if merr := ensure_parent_dirs(path); len(merr) > 0 {
		delete(path)
		return "", strings.clone(merr, allocator)
	}
	data := transmute([]u8)trimmed
	if werr := os.write_entire_file(path, data); werr != nil {
		delete(path)
		return "", fmt.aprintf("write plan failed: %v", werr, allocator = allocator)
	}
	return path, ""
}

/*
Parse FINDINGS: none or FINDINGS: N from the last lines of a review reply.
Returns (count, found). found=false when trailer missing.
*/
parse_findings_trailer :: proc(text: string) -> (count: int, found: bool) {
	lines := strings.split_lines(text, context.temp_allocator)
	for i := len(lines) - 1; i >= 0; i -= 1 {
		line := strings.trim_space(lines[i])
		if len(line) == 0 {
			continue
		}
		lower := strings.to_lower(line, context.temp_allocator)
		if !strings.has_prefix(lower, "findings:") {
			return 0, false
		}
		colon := strings.index_byte(line, ':')
		if colon < 0 {
			return 0, false
		}
		rest := strings.trim_space(line[colon + 1:])
		rest_l := strings.to_lower(rest, context.temp_allocator)
		if rest_l == "none" || rest_l == "0" {
			return 0, true
		}
		n, ok := strconv.parse_int(rest)
		if !ok || n < 0 {
			return 0, false
		}
		return n, true
	}
	return 0, false
}

fail_on_findings_from_env :: proc() -> bool {
	if v, ok := os.lookup_env(constants.ENV_FAIL_ON_FINDINGS, context.temp_allocator); ok {
		switch strings.to_lower(v, context.temp_allocator) {
		case "1", "true", "yes", "on":
			return true
		}
	}
	return false
}

bare_from_env :: proc() -> bool {
	if v, ok := os.lookup_env(constants.ENV_BARE, context.temp_allocator); ok {
		switch strings.to_lower(v, context.temp_allocator) {
		case "1", "true", "yes", "on":
			return true
		}
	}
	return false
}
