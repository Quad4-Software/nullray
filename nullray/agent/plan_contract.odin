// SPDX-License-Identifier: 0BSD
/*
Done Contract validation and plan apply notes.
*/

package agent

import "core:fmt"
import "core:strings"
import "nullray:constants"

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
