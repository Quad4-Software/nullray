// SPDX-License-Identifier: 0BSD
/*
Done Contract validation and plan apply notes.
*/

package agent

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "nullray:constants"
import "nullray:sandbox"

Done_Contract :: struct {
	goal:     string,
	verify:   string,
	success:  string,
	budget:   string,
	failure:  string,
	steps:    string,
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
	delete(c.steps)
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
	c.steps = section_body(body, "Steps", allocator)
	missing: strings.Builder
	strings.builder_init(&missing, context.temp_allocator)
	if len(c.steps) == 0 {
		strings.write_string(&missing, "Steps ")
	}
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

PLAN_EXAMPLE_INLINE :: `## Goal
Add a list_dir smoke test.

## Scope
nullray/tools tests only.

## Steps
1. Read existing list_dir tests.
2. Add one failing case for an empty path.
3. Run make test and fix until green.

## Risks
Sandbox workspace override in tests.

## Verify
make test

## Success
New test passes in the tools package.

## Budget
4

## Failure
Same failure twice after a fix attempt.
`

PLAN_EXAMPLE_PROMPT_CAP :: 600

/*
Load a short Done Contract example for plan-mode prompts. Prefer share file.
*/
load_plan_example_excerpt :: proc(allocator := context.allocator) -> string {
	roots := make([dynamic]string, context.temp_allocator)
	if exe, eerr := os.get_executable_path(context.temp_allocator); eerr == nil {
		exe_dir := filepath.dir(exe)
		append(&roots, fmt.tprintf("%s/../share/nullray/plan-example.md", exe_dir))
		append(&roots, fmt.tprintf("%s/share/nullray/plan-example.md", exe_dir))
	}
	if st := sandbox.state(); st != nil && len(st.workspace) > 0 {
		append(&roots, fmt.tprintf("%s/share/nullray/plan-example.md", st.workspace))
	}
	if cwd, cerr := os.get_working_directory(context.temp_allocator); cerr == nil {
		append(&roots, fmt.tprintf("%s/share/nullray/plan-example.md", cwd))
	}
	raw := ""
	for p in roots {
		if data, rerr := os.read_entire_file(p, context.temp_allocator); rerr == nil && len(data) > 0 {
			raw = string(data)
			break
		}
	}
	if len(raw) == 0 {
		raw = PLAN_EXAMPLE_INLINE
	}
	trimmed := strings.trim_space(raw)
	if len(trimmed) > PLAN_EXAMPLE_PROMPT_CAP {
		trimmed = trimmed[:PLAN_EXAMPLE_PROMPT_CAP]
	}
	return strings.clone(trimmed, allocator)
}

/*
Non-blocking hints for local models. Never flips valid to false.
*/
lint_plan_contract :: proc(body: string, allocator := context.allocator) -> string {
	c := validate_plan_contract(body)
	defer done_contract_destroy(&c)
	hints: strings.Builder
	strings.builder_init(&hints, context.temp_allocator)
	if len(c.steps) > 0 {
		numbered := false
		for line in strings.split_lines(c.steps, context.temp_allocator) {
			t := strings.trim_space(line)
			if len(t) == 0 {
				continue
			}
			if strings.has_prefix(t, "-") || strings.has_prefix(t, "*") {
				t = strings.trim_space(t[1:])
			}
			if len(t) >= 2 && t[0] >= '1' && t[0] <= '9' {
				rest := t[1:]
				if strings.has_prefix(rest, ".") || strings.has_prefix(rest, ")") {
					numbered = true
					break
				}
			}
		}
		if !numbered {
			strings.write_string(&hints, "Prefer numbered Steps (1. 2. 3.). ")
		}
	}
	if len(c.budget) > 0 {
		has_digit := false
		for r in c.budget {
			if r >= '0' && r <= '9' {
				has_digit = true
				break
			}
		}
		if !has_digit {
			strings.write_string(&hints, "Budget should include a number. ")
		}
	}
	if len(c.verify) > 0 {
		cmd := first_verify_command(c.verify, context.temp_allocator)
		if len(cmd) == 0 {
			strings.write_string(&hints, "Verify should list a runnable shell command. ")
		}
	}
	out := strings.trim_space(strings.to_string(hints))
	if len(out) == 0 {
		return ""
	}
	return strings.clone(out, allocator)
}

/*
User-facing repair note after an incomplete Done Contract. Cap length.
*/
plan_repair_nudge :: proc(err: string, body := "", allocator := context.allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	strings.write_string(&b, "Plan incomplete. Rewrite the full Done Contract in one reply with these exact headings:\n")
	strings.write_string(&b, "## Goal\n## Scope\n## Steps\n## Risks\n## Verify\n## Success\n## Budget\n## Failure\n")
	if len(err) > 0 {
		strings.write_string(&b, "Missing: ")
		strings.write_string(&b, err)
		strings.write_byte(&b, '\n')
	}
	if hint := lint_plan_contract(body, context.temp_allocator); len(hint) > 0 {
		strings.write_string(&b, "Hints: ")
		strings.write_string(&b, hint)
		strings.write_byte(&b, '\n')
	}
	strings.write_string(&b, "End the turn with only the markdown plan. Number Steps. Put a real shell command under Verify.\n")
	out := strings.to_string(b)
	if len(out) > 1200 {
		trimmed := strings.clone(out[:1200], allocator)
		delete(out)
		return trimmed
	}
	return out
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
Build apply note from full plan body (Goal, Verify, truncated Steps).
*/
plan_apply_note :: proc(body: string, budget_remaining: int, allocator := context.allocator) -> string {
	c := validate_plan_contract(body)
	defer done_contract_destroy(&c)
	note := plan_summary_note(c, budget_remaining, context.temp_allocator)
	steps := section_body(body, "Steps", context.temp_allocator)
	if len(steps) == 0 {
		return strings.clone(note, allocator)
	}
	b: strings.Builder
	strings.builder_init(&b, allocator)
	strings.write_string(&b, note)
	strings.write_string(&b, "Steps:\n")
	s := steps
	if len(s) > constants.MAX_PLAN_STEPS_NOTE_CHARS {
		s = s[:constants.MAX_PLAN_STEPS_NOTE_CHARS]
	}
	strings.write_string(&b, s)
	strings.write_byte(&b, '\n')
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
Rewrite architect child text into a parent-facing Done Contract handoff.
*/
format_architect_summary :: proc(raw: string, allocator := context.allocator) -> string {
	c := validate_plan_contract(raw)
	defer done_contract_destroy(&c)
	if c.valid {
		return strings.clone(strings.trim_space(raw), allocator)
	}
	b: strings.Builder
	strings.builder_init(&b, allocator)
	strings.write_string(&b, "architect plan incomplete")
	if len(c.err) > 0 {
		strings.write_string(&b, ": ")
		strings.write_string(&b, c.err)
	}
	strings.write_byte(&b, '\n')
	excerpt := strings.trim_space(raw)
	if len(excerpt) > 800 {
		excerpt = excerpt[:800]
	}
	if len(excerpt) > 0 {
		strings.write_string(&b, excerpt)
		strings.write_byte(&b, '\n')
	}
	return strings.to_string(b)
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
