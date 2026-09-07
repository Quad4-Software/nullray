/*
Chat session core: type, lifecycle, messages, mode, streaming, status.
*/

package session

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:sync"
import "nullray:agent"
import "nullray:constants"
import "nullray:provider"
import "nullray:store"
import "nullray:tools"

Session :: struct {
	messages:           [dynamic]provider.Message,
	busy:               bool,
	status:             string,
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
	reasoning_effort:   string,
	agent_mode:          agent.Agent_Mode,
	mode_policy:         agent.Mode_Policy,
	cancel_requested:    bool,
	pause_requested:     bool,
	control_mu:          sync.Mutex,
	turn_base:           int,
	pending_commit:      [dynamic]provider.Message,
	commit_mu:           sync.Mutex,
	skip_assistant_push: bool,
}

session_init :: proc(s: ^Session) {
	s^ = {}
	s.messages = make([dynamic]provider.Message)
	s.pending = make([dynamic]Event)
	s.pending_commit = make([dynamic]provider.Message)
	s.status = strings.clone("ready")
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
			s.session_path = strings.clone(v)
			s.name = strings.clone(filepath.stem(v))
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
	s.system_prompt = agent.build_system_prompt(skills_prompt)
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
	delete(s.status)
	delete(s.model)
	delete(s.provider_id)
	delete(s.system_prompt)
	delete(s.session_path)
	delete(s.name)
	delete(s.group)
	delete(s.reasoning_effort)
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

session_set_status :: proc(s: ^Session, text: string) {
	delete(s.status)
	s.status = strings.clone(text)
}

session_push_user :: proc(s: ^Session, text: string) {
	if s.mode_policy == .Auto {
		suggested := agent.auto_suggest_mode(text)
		if suggested != s.agent_mode {
			session_set_mode(s, suggested)
		}
	}
	cap_messages(s)
	append(&s.messages, provider.Message{role = .User, content = strings.clone(text)})
	session_maybe_persist(s)
}

session_push_assistant :: proc(s: ^Session, text: string, reasoning := "") {
	cap_messages(s)
	append(&s.messages, provider.Message{
		role = .Assistant,
		content = strings.clone(text),
		reasoning = strings.clone(reasoning),
	})
	session_maybe_persist(s)
}

session_push_tool :: proc(s: ^Session, name, text: string) {
	cap_messages(s)
	append(&s.messages, provider.Message{
		role = .Tool,
		content = strings.clone(text),
		name = strings.clone(name),
	})
	session_maybe_persist(s)
}

@(private)
cap_messages :: proc(s: ^Session) {
	if len(s.messages) >= constants.MAX_MESSAGES {
		old := s.messages[0]
		provider.destroy_message(old)
		ordered_remove(&s.messages, 0)
	}
	session_trim_memory(s, mem_max_chars_from_env())
}

ephemeral_from_env :: proc() -> bool {
	if v, ok := os.lookup_env(constants.ENV_EPHEMERAL, context.temp_allocator); ok {
		switch strings.to_lower(v, context.temp_allocator) {
		case "1", "true", "yes", "on":
			return true
		}
	}
	return false
}

group_context_from_env :: proc() -> bool {
	if v, ok := os.lookup_env(constants.ENV_GROUP_CONTEXT, context.temp_allocator); ok {
		switch strings.to_lower(v, context.temp_allocator) {
		case "0", "false", "no", "off":
			return false
		}
	}
	return true
}

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

session_sync_mode_env :: proc(s: ^Session) {
	os.set_env(constants.ENV_MODE, agent.mode_string(s.agent_mode))
	os.set_env(constants.ENV_MODE_POLICY, agent.policy_string(s.mode_policy))
}

session_rebuild_system_prompt :: proc(s: ^Session) {
	delete(s.system_prompt)
	skills_prompt := agent.load_skills_prompt()
	s.system_prompt = agent.build_system_prompt(skills_prompt)
	delete(skills_prompt)
}

session_set_mode :: proc(s: ^Session, mode: agent.Agent_Mode) {
	s.agent_mode = mode
	session_sync_mode_env(s)
	session_rebuild_system_prompt(s)
	session_save_meta(s)
	session_set_status(s, fmt.tprintf("mode %s", agent.mode_string(mode)))
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

session_clear_streaming :: proc(s: ^Session) {
	strings.builder_reset(&s.streaming)
	s.has_streaming = false
	strings.builder_reset(&s.thinking)
	s.has_thinking = false
}

session_append_delta :: proc(s: ^Session, text: string) {
	cur := strings.builder_len(s.streaming)
	if cur >= constants.MAX_STREAMING_CHARS {
		s.has_streaming = true
		return
	}
	remain := constants.MAX_STREAMING_CHARS - cur
	chunk := text
	if len(chunk) > remain {
		chunk = chunk[:remain]
	}
	strings.write_string(&s.streaming, chunk)
	s.has_streaming = true
}

session_append_thinking :: proc(s: ^Session, text: string) {
	cur := strings.builder_len(s.thinking)
	if cur >= constants.MAX_STREAMING_CHARS {
		s.has_thinking = true
		return
	}
	remain := constants.MAX_STREAMING_CHARS - cur
	chunk := text
	if len(chunk) > remain {
		chunk = chunk[:remain]
	}
	strings.write_string(&s.thinking, chunk)
	s.has_thinking = true
}

session_ready_status :: proc(s: ^Session) -> string {
	mode := agent.mode_string(s.agent_mode)
	perms := tools.perms_string(tools.perms_from_env())
	auto := ""
	if agent.auto_from_env() {
		auto = " auto"
	}
	if s.last_usage.total_tokens <= 0 {
		return fmt.tprintf("ready · %s · %s%s", mode, perms, auto)
	}
	return fmt.tprintf(
		"ready · %s · %s%s · %s in / %s out · sess %s",
		mode,
		perms,
		auto,
		format_token_count(s.last_usage.prompt_tokens),
		format_token_count(s.last_usage.completion_tokens),
		format_token_count(s.session_usage.total_tokens),
	)
}

session_usage_label :: proc(s: ^Session, allocator := context.allocator) -> string {
	if s.last_usage.total_tokens <= 0 && s.session_usage.total_tokens <= 0 {
		return strings.clone("", allocator)
	}
	return fmt.aprintf(
		"%s/%s tok",
		format_token_count(s.last_usage.total_tokens),
		format_token_count(s.session_usage.total_tokens),
		allocator = allocator,
	)
}

@(private)
format_token_count :: proc(n: int) -> string {
	if n < 1000 {
		return fmt.tprintf("%d", n)
	}
	if n < 10_000 {
		return fmt.tprintf("%.1fk", f64(n) / 1000.0)
	}
	return fmt.tprintf("%dk", n / 1000)
}

