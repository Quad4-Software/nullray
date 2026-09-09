// SPDX-License-Identifier: 0BSD
package session

import "core:fmt"
import "core:os"
import "core:strings"
import "nullray:agent"
import "nullray:constants"
import "nullray:provider"

session_remember_model :: proc(s: ^Session, provider_id, model: string) {
	if len(provider_id) > 0 {
		delete(s.provider_id)
		s.provider_id = strings.clone(provider_id)
	}
	if len(model) > 0 {
		delete(s.model)
		s.model = strings.clone(model)
	}
	session_save_meta(s)
}

// Persist auto-selected live local provider when env did not name one.
session_sticky_auto_provider :: proc(s: ^Session, reg: ^provider.Registry) {
	if s == nil || reg == nil || !s.persist || len(s.provider_id) > 0 {
		return
	}
	if provider.provider_env_set() {
		return
	}
	p := provider.registry_active(reg)
	if p == nil || !provider.provider_is_local(p.id) {
		return
	}
	if provider.provider_readiness_label(p, true) != "live" {
		return
	}
	session_remember_model(s, p.id, p.default_model)
}

session_sync_mode_env :: proc(s: ^Session) {
	os.set_env(constants.ENV_MODE, agent.mode_string(s.agent_mode))
	os.set_env(constants.ENV_MODE_POLICY, agent.policy_string(s.mode_policy))
}

session_rebuild_system_prompt :: proc(s: ^Session, retrieve_query: string = "") {
	delete(s.system_prompt)
	skills_prompt := agent.load_skills_prompt()
	q := retrieve_query
	if len(q) == 0 {
		q = session_last_user_text(s)
	}
	s.system_prompt = agent.build_system_prompt(skills_prompt, s.tools_registry, q)
	delete(skills_prompt)
}

session_last_user_text :: proc(s: ^Session) -> string {
	if s == nil {
		return ""
	}
	for i := len(s.messages) - 1; i >= 0; i -= 1 {
		if s.messages[i].role == .User {
			return s.messages[i].content
		}
	}
	return ""
}

session_set_mode :: proc(s: ^Session, mode: agent.Agent_Mode) {
	prev := s.agent_mode
	if mode == .Edit && prev == .Plan && !s.plan_contract_ok {
		if s.mode_policy == .Auto || s.mode_policy == .Model {
			session_set_status(s, "plan incomplete (need Steps, Verify, Success, Budget) before edit")
			return
		}
	}
	s.agent_mode = mode
	session_sync_mode_env(s)
	session_rebuild_system_prompt(s)
	session_save_meta(s)
	if prev != mode {
		session_phase_reset_provider_window(s)
	}
	if mode == .Edit && (len(s.plan_verify) > 0 || s.plan_contract_ok) {
		// Only inject on Plan -> Edit transition to avoid duplicate notes.
		if prev == .Plan {
			note: string
			if len(s.plan_body) > 0 {
				if len(s.plan_steps) == 0 {
					session_seed_plan_steps(s, s.plan_body, s.last_plan_path, true)
				}
				note = session_plan_step_note(s, context.temp_allocator)
			} else {
				c := agent.Done_Contract{
					verify = s.plan_verify,
					valid = s.plan_contract_ok,
				}
				note = agent.plan_summary_note(c, verify_max_remaining(s), context.temp_allocator)
			}
			if len(note) > 0 {
				session_push_user(s, note)
			}
		}
	}
	session_set_status(s, fmt.tprintf("mode %s", agent.mode_string(mode)))
}

verify_max_remaining :: proc(s: ^Session) -> int {
	max_fails := agent.verify_max_fails_from_env()
	left := max_fails - s.verify_fail_count
	if left < 0 {
		return 0
	}
	return left
}

session_load_plan_contract :: proc(s: ^Session, body: string) {
	delete(s.plan_verify)
	s.plan_verify = ""
	s.plan_contract_ok = false
	c := agent.validate_plan_contract(body)
	defer agent.done_contract_destroy(&c)
	if c.valid {
		s.plan_contract_ok = true
		s.plan_verify = strings.clone(c.verify)
	}
}

/*
Seed session from a validated plan body without switching mode.
Caller owns path/body clones stored on the session.
*/
session_seed_plan :: proc(s: ^Session, path: string, body: string) -> string {
	if s == nil {
		return "nil session"
	}
	trimmed_path := strings.trim_space(path)
	trimmed_body := strings.trim_space(body)
	if len(trimmed_path) == 0 {
		return "plan path empty"
	}
	if len(trimmed_body) == 0 {
		return "plan body empty"
	}
	session_load_plan_contract(s, trimmed_body)
	if !s.plan_contract_ok {
		return "plan still missing Verify/Success/Budget"
	}
	delete(s.last_plan_path)
	s.last_plan_path = strings.clone(trimmed_path)
	delete(s.plan_body)
	s.plan_body = strings.clone(trimmed_body)
	session_seed_plan_steps(s, trimmed_body, trimmed_path, true)
	return ""
}

session_seed_plan_file :: proc(s: ^Session, path: string) -> string {
	body, err := agent.load_plan_file(path)
	if len(err) > 0 {
		return err
	}
	defer delete(body)
	return session_seed_plan(s, path, body)
}

/*
Load plan file, seed contract, switch to edit (injects apply note).
*/
session_approve_plan_file :: proc(s: ^Session, path: string) -> string {
	body, err := agent.load_plan_file(path)
	if len(err) > 0 {
		return err
	}
	defer delete(body)
	if serr := session_seed_plan(s, path, body); len(serr) > 0 {
		return serr
	}
	s.plan_contract_ok = true
	session_set_mode(s, .Edit)
	return ""
}

session_apply_saved_model :: proc(s: ^Session, reg: ^provider.Registry) -> bool {
	if reg == nil {
		return false
	}
	changed := false
	if len(s.provider_id) > 0 {
		if provider.registry_set_active(reg, s.provider_id) {
			changed = true
		}
	}
	p := provider.registry_active(reg)
	if p != nil && len(s.model) > 0 {
		delete(p.default_model)
		p.default_model = strings.clone(s.model)
		changed = true
	}
	return changed
}
