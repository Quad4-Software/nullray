// SPDX-License-Identifier: 0BSD
/*
Parse Done Contract Steps and persist step-anchor sidecars.
*/

package agent

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "nullray:constants"

MAX_PLAN_STEPS :: 32

/*
Parse Steps section into ordered step strings. Prefers numbered lines.
Fallback: non-empty bullets or paragraphs. Caller owns the dynamic and strings.
*/
parse_plan_steps :: proc(steps_section: string, allocator := context.allocator) -> [dynamic]string {
	out := make([dynamic]string, allocator)
	lines := strings.split_lines(steps_section, context.temp_allocator)
	numbered: [dynamic]string
	fallback: [dynamic]string
	defer {
		delete(numbered)
		delete(fallback)
	}
	for line in lines {
		t := strings.trim_space(line)
		if len(t) == 0 {
			continue
		}
		bullet := false
		if strings.has_prefix(t, "-") || strings.has_prefix(t, "*") {
			t = strings.trim_space(t[1:])
			bullet = true
		}
		if len(t) == 0 {
			continue
		}
		num_end := 0
		for num_end < len(t) && t[num_end] >= '0' && t[num_end] <= '9' {
			num_end += 1
		}
		if num_end > 0 && num_end < len(t) && (t[num_end] == '.' || t[num_end] == ')') {
			rest := strings.trim_space(t[num_end + 1:])
			if len(rest) > 0 {
				append(&numbered, rest)
				continue
			}
		}
		if bullet || len(t) > 0 {
			append(&fallback, t)
		}
	}
	src := numbered[:]
	if len(src) == 0 {
		src = fallback[:]
	}
	for s, i in src {
		if i >= MAX_PLAN_STEPS {
			break
		}
		append(&out, strings.clone(s, allocator))
	}
	return out
}

plan_steps_destroy :: proc(steps: ^[dynamic]string) {
	if steps == nil {
		return
	}
	for s in steps {
		delete(s)
	}
	delete(steps^)
	steps^ = {}
}

/*
Build current-step apply note. When steps empty, falls back to full Steps dump.
*/
plan_step_apply_note :: proc(
	body: string,
	step_index: int,
	steps: []string,
	budget_remaining: int,
	allocator := context.allocator,
) -> string {
	c := validate_plan_contract(body)
	defer done_contract_destroy(&c)
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
	if len(c.success) > 0 {
		strings.write_string(&b, "Success: ")
		s := c.success
		if len(s) > 200 {
			s = s[:200]
		}
		strings.write_string(&b, s)
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
	if len(steps) == 0 {
		strings.builder_destroy(&b)
		return plan_apply_note(body, budget_remaining, allocator)
	}
	idx := step_index
	if idx < 0 {
		idx = 0
	}
	if idx >= len(steps) {
		strings.write_string(&b, "All plan steps are complete. Stop or ask for a new plan.\n")
		return strings.to_string(b)
	}
	fmt.sbprintf(&b, "Current step %d/%d:\n", idx + 1, len(steps))
	step := steps[idx]
	if len(step) > constants.MAX_PLAN_STEPS_NOTE_CHARS {
		step = step[:constants.MAX_PLAN_STEPS_NOTE_CHARS]
	}
	strings.write_string(&b, step)
	strings.write_byte(&b, '\n')
	strings.write_string(&b, "Implement only this step. Do not skip ahead. Say when the step is done.\n")
	return strings.to_string(b)
}

Plan_Steps_Sidecar :: struct {
	index: int,
	steps: [dynamic]string,
	done:  [dynamic]bool,
}

plan_steps_sidecar_destroy :: proc(sc: ^Plan_Steps_Sidecar) {
	if sc == nil {
		return
	}
	for s in sc.steps {
		delete(s)
	}
	delete(sc.steps)
	delete(sc.done)
	sc^ = {}
}

plan_steps_sidecar_path :: proc(plan_path: string, allocator := context.allocator) -> string {
	return fmt.aprintf("%s.steps.json", plan_path, allocator = allocator)
}

write_plan_steps_sidecar :: proc(
	plan_path: string,
	index: int,
	steps: []string,
	allocator := context.allocator,
) -> string {
	if len(strings.trim_space(plan_path)) == 0 {
		return strings.clone("empty plan path", allocator)
	}
	path := plan_steps_sidecar_path(plan_path, context.temp_allocator)
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	strings.write_string(&b, "{\"index\":")
	fmt.sbprintf(&b, "%d", index)
	strings.write_string(&b, ",\"steps\":[")
	for s, i in steps {
		if i > 0 {
			strings.write_byte(&b, ',')
		}
		escaped, merr := json.marshal(s, allocator = context.temp_allocator)
		if merr != nil {
			return fmt.aprintf("marshal step failed: %v", merr, allocator = allocator)
		}
		strings.write_bytes(&b, escaped)
	}
	strings.write_string(&b, "],\"done\":[")
	for i in 0 ..< len(steps) {
		if i > 0 {
			strings.write_byte(&b, ',')
		}
		if i < index {
			strings.write_string(&b, "true")
		} else {
			strings.write_string(&b, "false")
		}
	}
	strings.write_string(&b, "]}")
	if merr := ensure_parent_dirs(path); len(merr) > 0 {
		return strings.clone(merr, allocator)
	}
	if werr := os.write_entire_file(path, transmute([]u8)strings.to_string(b)); werr != nil {
		return fmt.aprintf("write steps sidecar failed: %v", werr, allocator = allocator)
	}
	return ""
}

/*
Load sidecar if present. On failure returns empty steps and err.
Caller owns returned steps strings.
*/
read_plan_steps_sidecar :: proc(
	plan_path: string,
	allocator := context.allocator,
) -> (index: int, steps: [dynamic]string, err: string) {
	steps = make([dynamic]string, allocator)
	path := plan_steps_sidecar_path(plan_path, context.temp_allocator)
	data, rerr := os.read_entire_file(path, context.temp_allocator)
	if rerr != nil {
		return 0, steps, fmt.aprintf("read steps sidecar failed: %v", rerr, allocator = allocator)
	}
	val, jerr := json.parse(data, .JSON, allocator = context.temp_allocator)
	if jerr != nil {
		return 0, steps, strings.clone("steps sidecar json invalid", allocator)
	}
	obj, ok := val.(json.Object)
	if !ok {
		return 0, steps, strings.clone("steps sidecar not an object", allocator)
	}
	if iv, iok := obj["index"]; iok {
		#partial switch v in iv {
		case json.Integer:
			index = int(v)
		case json.Float:
			index = int(v)
		case json.String:
			if n, pok := strconv.parse_int(string(v)); pok {
				index = n
			}
		}
	}
	if sv, sok := obj["steps"]; sok {
		if arr, aok := sv.(json.Array); aok {
			for item in arr {
				if s, sok2 := item.(json.String); sok2 {
					append(&steps, strings.clone(string(s), allocator))
				}
			}
		}
	}
	if index < 0 {
		index = 0
	}
	if index > len(steps) {
		index = len(steps)
	}
	return index, steps, ""
}
