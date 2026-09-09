// SPDX-License-Identifier: 0BSD
/*
Chat session core: type, lifecycle, messages, mode, streaming, status.
*/

package session

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"
import "nullray:agent"
import "nullray:constants"
import "nullray:provider"
import "nullray:store"
import "nullray:tools"

Session :: struct {
	messages:           [dynamic]provider.Message,
	busy:               bool,
	status:             string,
	pending_status:     string,
	status_set_at:      time.Tick,
	pending:            [dynamic]Event,
	pending_mu:         sync.Mutex,
	model:              string,
	provider_id:        string,
	tools_enabled:      bool,
	system_prompt:      string,
	session_path:       string,
	persist:            bool,
	streaming:          strings.Builder,
	has_streaming:      bool,
	thinking:           strings.Builder,
	has_thinking:       bool,
	name:               string,
	group:              string,
	last_usage:         provider.Usage,
	session_usage:      provider.Usage,
	subagent_total_tokens: int,
	usage_turns:        int,
	peak_input_chars:   int,
	last_stopped:       string,
	reasoning_effort:   string,
	agent_mode:          agent.Agent_Mode,
	tools_registry:      ^tools.Registry,
	mode_policy:         agent.Mode_Policy,
	cancel_requested:    bool,
	pause_requested:     bool,
	control_mu:          sync.Mutex,
	job_mu:              sync.Mutex,
	job_thread:          ^thread.Thread,
	turn_base:           int,
	pending_commit:      [dynamic]provider.Message,
	commit_mu:           sync.Mutex,
	skip_assistant_push: bool,
	last_plan_path:      string,
	plan_body:           string,
	plan_verify:         string,
	plan_contract_ok:    bool,
	pending_plan_nudge:  string,
	pending_step_note:   string,
	plan_steps:          [dynamic]string,
	plan_step_index:     int,
	plan_steps_path:     string,
	verify_fail_count:   int,
	last_input_chars:    int,
	verify_obligations:  [dynamic]string,
	live_tool:           string,
	live_tool_detail:    string,
}

session_init :: proc(s: ^Session) {
	s^ = {}
	s.messages = make([dynamic]provider.Message)
	s.pending = make([dynamic]Event)
	s.pending_commit = make([dynamic]provider.Message)
	s.verify_obligations = make([dynamic]string)
	s.plan_steps = make([dynamic]string)
	s.status = strings.clone("ready")
	s.status_set_at = time.tick_now()
	s.tools_enabled = tools_enabled_from_env()
	s.persist = !ephemeral_from_env()
	strings.builder_init(&s.streaming)
	strings.builder_init(&s.thinking)
	s.reasoning_effort = strings.clone(reasoning_effort_from_env())
	s.agent_mode = agent.mode_from_env()
	s.mode_policy = agent.policy_from_env()
	if v, ok := os.lookup_env(constants.ENV_SESSION, context.temp_allocator); ok {
		if v == "off" || v == "0" || v == "false" {
			s.persist = false
		} else if len(v) > 0 && v != "on" && v != "1" && v != "true" {
			if store.looks_like_session_path(v) {
				s.session_path = strings.clone(v)
				s.name = strings.clone(filepath.stem(v))
			} else {
				safe := store.sanitize_name(v)
				s.name = strings.clone(safe)
				s.session_path = store.named_session_path(safe)
			}
		}
	}
	if len(s.session_path) == 0 {
		s.session_path = store.default_session_path()
		s.name = strings.clone(filepath.stem(s.session_path))
	}
	if ok, holder := store.session_try_lock(s.session_path); !ok {
		session_set_status(s, fmt.tprintf("session locked by %s (read-only risk)", holder))
	}

	skills_prompt := agent.load_skills_prompt()
	s.system_prompt = agent.build_system_prompt(skills_prompt, s.tools_registry)
	delete(skills_prompt)

	if s.persist {
		loaded, ok := store.load_transcript(s.session_path)
		if ok {
			for m in loaded {
				append(&s.messages, m)
			}
			delete(loaded)
		}
		session_load_meta(s)
		session_rebuild_system_prompt(s)
		session_trim_memory(s, mem_max_chars_from_env())
	} else {
		session_set_status(s, "ephemeral (not saving)")
	}
	session_sync_mode_env(s)
}

session_destroy :: proc(s: ^Session) {
	session_shutdown(s)
	_ = store.artifact_gc()
	if len(s.session_path) > 0 {
		store.session_unlock(s.session_path)
	}
	for m in s.messages {
		provider.destroy_message(m)
	}
	delete(s.messages)
	sync.mutex_lock(&s.pending_mu)
	for e in s.pending {
		delete(e.text)
		delete(e.name)
		delete(e.reasoning)
	}
	delete(s.pending)
	sync.mutex_unlock(&s.pending_mu)
	sync.mutex_lock(&s.commit_mu)
	for m in s.pending_commit {
		provider.destroy_message(m)
	}
	delete(s.pending_commit)
	sync.mutex_unlock(&s.commit_mu)
	delete(s.status)
	delete(s.pending_status)
	delete(s.model)
	delete(s.provider_id)
	delete(s.system_prompt)
	delete(s.session_path)
	delete(s.name)
	delete(s.group)
	delete(s.reasoning_effort)
	delete(s.last_plan_path)
	delete(s.plan_body)
	delete(s.plan_verify)
	delete(s.pending_plan_nudge)
	delete(s.pending_step_note)
	session_clear_plan_steps(s)
	delete(s.plan_steps_path)
	delete(s.live_tool)
	delete(s.live_tool_detail)
	delete(s.last_stopped)
	session_clear_verify_obligations(s)
	delete(s.verify_obligations)
	strings.builder_destroy(&s.streaming)
	strings.builder_destroy(&s.thinking)
	s^ = {}
}

tools_enabled_from_env :: proc() -> bool {
	if v, ok := os.lookup_env(constants.ENV_AGENT_TOOLS, context.temp_allocator); ok {
		switch strings.to_lower(v, context.temp_allocator) {
		case "0", "false", "off", "no":
			return false
		}
	}
	return true
}

reasoning_effort_from_env :: proc() -> string {
	if v, ok := os.lookup_env(constants.ENV_REASONING, context.temp_allocator); ok && len(v) > 0 {
		return strings.to_lower(v, context.temp_allocator)
	}
	return constants.DEFAULT_REASONING
}

normalize_reasoning_effort :: proc(raw: string) -> (string, bool) {
	e := strings.to_lower(strings.trim_space(raw), context.temp_allocator)
	switch e {
	case "none", "off", "0", "false":
		return "none", true
	case "minimal", "min":
		return "minimal", true
	case "low":
		return "low", true
	case "medium", "med", "default":
		return "medium", true
	case "high":
		return "high", true
	case "xhigh", "max":
		return e, true
	}
	return "", false
}
