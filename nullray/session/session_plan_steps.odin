// SPDX-License-Identifier: 0BSD
/*
Session helpers for Done Contract step anchoring.
*/

package session

import "core:strings"
import "nullray:agent"

session_clear_plan_steps :: proc(s: ^Session) {
	if s == nil {
		return
	}
	for step in s.plan_steps {
		delete(step)
	}
	delete(s.plan_steps)
	s.plan_steps = make([dynamic]string)
	s.plan_step_index = 0
}

session_seed_plan_steps :: proc(s: ^Session, body: string, plan_path: string, reset_index := true) {
	if s == nil {
		return
	}
	session_clear_plan_steps(s)
	steps_sec := agent.section_body(body, "Steps", context.temp_allocator)
	parsed := agent.parse_plan_steps(steps_sec)
	defer agent.plan_steps_destroy(&parsed)
	for step in parsed {
		append(&s.plan_steps, strings.clone(step))
	}
	if reset_index {
		s.plan_step_index = 0
	} else if len(plan_path) > 0 {
		idx, loaded, err := agent.read_plan_steps_sidecar(plan_path)
		if len(err) == 0 && len(loaded) > 0 {
			session_clear_plan_steps(s)
			for step in loaded {
				append(&s.plan_steps, strings.clone(step))
			}
			s.plan_step_index = idx
			agent.plan_steps_destroy(&loaded)
		} else {
			delete(err)
			agent.plan_steps_destroy(&loaded)
			s.plan_step_index = 0
		}
	}
	delete(s.plan_steps_path)
	s.plan_steps_path = ""
	if len(plan_path) > 0 {
		s.plan_steps_path = agent.plan_steps_sidecar_path(plan_path)
		_ = agent.write_plan_steps_sidecar(plan_path, s.plan_step_index, s.plan_steps[:])
	}
}

session_plan_step_note :: proc(s: ^Session, allocator := context.allocator) -> string {
	if s == nil {
		return ""
	}
	body := s.plan_body
	if len(body) == 0 {
		return ""
	}
	return agent.plan_step_apply_note(
		body,
		s.plan_step_index,
		s.plan_steps[:],
		verify_max_remaining(s),
		allocator,
	)
}

/*
Advance to the next plan step after a successful edit turn. Returns true if advanced or completed.
When queue_note is true, stores the next-step note for Assistant_Done injection.
*/
session_advance_plan_step :: proc(s: ^Session, queue_note: bool) -> bool {
	if s == nil || !s.plan_contract_ok || len(s.plan_steps) == 0 {
		return false
	}
	if s.plan_step_index >= len(s.plan_steps) {
		return false
	}
	step_text := s.plan_steps[s.plan_step_index]
	_ = agent.write_plan_rewind_checkpoint(s.plan_step_index, step_text, "step completed")
	s.plan_step_index += 1
	if len(s.last_plan_path) > 0 {
		_ = agent.write_plan_steps_sidecar(s.last_plan_path, s.plan_step_index, s.plan_steps[:])
	}
	if s.plan_step_index >= len(s.plan_steps) {
		session_enqueue(s, Event{kind = .Status, text = strings.clone("plan steps complete")})
		return true
	}
	if queue_note {
		note := session_plan_step_note(s)
		delete(s.pending_step_note)
		s.pending_step_note = note
	}
	return true
}

/*
Push current-step apply note if missing. Used by --plan-in when already in edit.
*/
session_ensure_plan_step_note :: proc(s: ^Session) {
	if s == nil || !s.plan_contract_ok || len(s.plan_body) == 0 {
		return
	}
	for i := len(s.messages) - 1; i >= 0 && i >= len(s.messages) - 4; i -= 1 {
		m := s.messages[i]
		if m.role == .User && strings.contains(m.content, "Current step") {
			return
		}
		if m.role == .User && strings.contains(m.content, "Active plan (Done Contract)") {
			return
		}
	}
	note := session_plan_step_note(s)
	if len(note) == 0 {
		return
	}
	session_push_user(s, note)
	delete(note)
}
