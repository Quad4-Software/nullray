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

Done_Contract :: struct {
	goal:     string,
	verify:   string,
	success:  string,
	budget:   string,
	failure:  string,
	valid:    bool,
	err:      string,
}

done_contract_destroy :: proc(c: ^Done_Contract) {
	if c == nil {
		return
	}
	delete(c.goal)
	delete(c.verify)
	delete(c.success)
	delete(c.budget)
	delete(c.failure)
	delete(c.err)
	c^ = {}
}

section_body :: proc(text, heading: string, allocator := context.allocator) -> string {
	lines := strings.split_lines(text, context.temp_allocator)
	want := strings.to_lower(heading, context.temp_allocator)
	start := -1
	for line, i in lines {
		trimmed := strings.trim_space(line)
		if !strings.has_prefix(trimmed, "##") {
			continue
		}
		title := strings.trim_space(trimmed[2:])
		for strings.has_prefix(title, "#") {
			title = strings.trim_space(title[1:])
		}
		if strings.to_lower(title, context.temp_allocator) == want {
			start = i + 1
			break
		}
	}
	if start < 0 {
		return ""
	}
	end := len(lines)
	for i in start ..< len(lines) {
		trimmed := strings.trim_space(lines[i])
		if strings.has_prefix(trimmed, "##") {
			end = i
			break
		}
	}
	if start >= end {
		return ""
	}
	return strings.clone(strings.trim_space(strings.join(lines[start:end], "\n", context.temp_allocator)), allocator)
}

/*
Validate required Done Contract sections. Caller owns returned contract strings.
*/
validate_plan_contract :: proc(body: string, allocator := context.allocator) -> Done_Contract {
	c: Done_Contract
	c.goal = section_body(body, "Goal", allocator)
	c.verify = section_body(body, "Verify", allocator)
	c.success = section_body(body, "Success", allocator)
	c.budget = section_body(body, "Budget", allocator)
	c.failure = section_body(body, "Failure", allocator)
	missing: strings.Builder
	strings.builder_init(&missing, context.temp_allocator)
	if len(c.verify) == 0 {
		strings.write_string(&missing, "Verify ")
	}
	if len(c.success) == 0 {
		strings.write_string(&missing, "Success ")
	}
	if len(c.budget) == 0 {
		strings.write_string(&missing, "Budget ")
	}
	miss := strings.trim_space(strings.to_string(missing))
	if len(miss) > 0 {
		c.valid = false
		c.err = fmt.aprintf("plan missing required sections: %s", miss, allocator = allocator)
		return c
	}
	c.valid = true
	return c
}

/*
Short volatile-tail reminder from a validated contract.
*/
plan_summary_note :: proc(c: Done_Contract, budget_remaining: int, allocator := context.allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	strings.write_string(&b, "Active plan (Done Contract):\n")
	if len(c.goal) > 0 {
		strings.write_string(&b, "Goal: ")
		g := c.goal
		if len(g) > 240 {
			g = g[:240]
		}
		strings.write_string(&b, g)
		strings.write_byte(&b, '\n')
	}
	strings.write_string(&b, "Verify:\n")
	v := c.verify
	if len(v) > 800 {
		v = v[:800]
	}
	strings.write_string(&b, v)
	strings.write_byte(&b, '\n')
	if budget_remaining >= 0 {
		fmt.sbprintf(&b, "Budget remaining (verify retries / steps hint): %d\n", budget_remaining)
	}
	return strings.to_string(b)
}

/*
Parse first shell-like verify command from a Verify section (first non-empty line, strip leading - or *).
*/
first_verify_command :: proc(verify_section: string, allocator := context.allocator) -> string {
	lines := strings.split_lines(verify_section, context.temp_allocator)
	for line in lines {
		t := strings.trim_space(line)
		if len(t) == 0 {
			continue
		}
		if strings.has_prefix(t, "-") || strings.has_prefix(t, "*") {
			t = strings.trim_space(t[1:])
		}
		if strings.has_prefix(t, "`") && strings.has_suffix(t, "`") && len(t) >= 2 {
			t = t[1:len(t) - 1]
		}
		if len(t) == 0 {
			continue
		}
		return strings.clone(t, allocator)
	}
	return ""
}

/*
Extract Verify: command lines from AGENTS.md-style contract text.
*/
parse_agents_verify_commands :: proc(agents_text: string, allocator := context.allocator) -> [dynamic]string {
	out := make([dynamic]string, allocator)
	lines := strings.split_lines(agents_text, context.temp_allocator)
	in_verify := false
	for line in lines {
		trimmed := strings.trim_space(line)
		lower := strings.to_lower(trimmed, context.temp_allocator)
		if strings.has_prefix(lower, "verify:") {
			rest := strings.trim_space(trimmed[len("verify:"):])
			if len(rest) > 0 {
				append(&out, strings.clone(rest, allocator))
			}
			in_verify = true
			continue
		}
		if strings.has_prefix(trimmed, "##") || strings.has_prefix(trimmed, "# ") {
			in_verify = false
			continue
		}
		if in_verify {
			if len(trimmed) == 0 {
				continue
			}
			if strings.has_prefix(trimmed, "-") || strings.has_prefix(trimmed, "*") {
				trimmed = strings.trim_space(trimmed[1:])
			}
			if len(trimmed) > 0 {
				append(&out, strings.clone(trimmed, allocator))
			}
		}
	}
	return out
}

