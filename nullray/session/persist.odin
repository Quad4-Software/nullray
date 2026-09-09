// SPDX-License-Identifier: 0BSD
/*
Session persistence, identity CRUD, list and search.
*/

package session

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "nullray:agent"
import "nullray:provider"
import "nullray:store"

session_maybe_persist :: proc(s: ^Session) {
	if s.persist && len(s.session_path) > 0 {
		_ = store.save_transcript(s.session_path, s.messages[:])
		session_save_meta(s)
	}
}

session_set_ephemeral :: proc(s: ^Session, on: bool) {
	s.persist = !on
	if on {
		session_set_status(s, "ephemeral on (not saving)")
	} else {
		session_maybe_persist(s)
		session_set_status(s, "ephemeral off (saving)")
	}
}

session_set_group :: proc(s: ^Session, group: string) {
	delete(s.group)
	g := strings.trim_space(group)
	if len(g) == 0 || g == "none" || g == "off" {
		s.group = strings.clone("")
		session_maybe_persist(s)
		session_set_status(s, "group cleared")
		return
	}
	s.group = strings.clone(store.sanitize_name(g))
	session_maybe_persist(s)
	session_set_status(s, fmt.tprintf("group %s", s.group))
}

session_save_meta :: proc(s: ^Session) {
	if !s.persist || len(s.session_path) == 0 {
		return
	}
	_ = store.save_session_meta(s.session_path, store.Session_Meta{
		provider = s.provider_id,
		model = s.model,
		group = s.group,
		mode = agent.mode_string(s.agent_mode),
		turns = s.usage_turns,
		prompt_tokens = s.session_usage.prompt_tokens,
		completion_tokens = s.session_usage.completion_tokens,
		total_tokens = s.session_usage.total_tokens,
		reasoning_tokens = s.session_usage.reasoning_tokens,
		cost_usd = s.session_usage.cost_usd,
		cost_known = s.session_usage.cost_known,
		peak_input_chars = s.peak_input_chars,
		last_input_chars = s.last_input_chars,
		subagent_total_tokens = s.subagent_total_tokens,
	})
}

session_load_meta :: proc(s: ^Session) {
	meta, ok := store.load_session_meta(s.session_path)
	if !ok {
		session_reload_usage(s)
		return
	}
	defer store.destroy_session_meta(meta)
	if len(meta.provider) > 0 {
		delete(s.provider_id)
		s.provider_id = strings.clone(meta.provider)
	}
	if len(meta.model) > 0 {
		delete(s.model)
		s.model = strings.clone(meta.model)
	}
	if len(meta.group) > 0 {
		delete(s.group)
		s.group = strings.clone(meta.group)
	}
	if len(meta.mode) > 0 {
		if m, mok := agent.mode_from_string(meta.mode); mok {
			s.agent_mode = m
		}
	}
	session_reset_usage(s)
	s.usage_turns = meta.turns
	s.session_usage.prompt_tokens = meta.prompt_tokens
	s.session_usage.completion_tokens = meta.completion_tokens
	s.session_usage.total_tokens = meta.total_tokens
	s.session_usage.reasoning_tokens = meta.reasoning_tokens
	s.session_usage.cost_usd = meta.cost_usd
	s.session_usage.cost_known = meta.cost_known
	s.peak_input_chars = meta.peak_input_chars
	s.last_input_chars = meta.last_input_chars
	s.subagent_total_tokens = meta.subagent_total_tokens
	session_overlay_usage_file(s)
}

session_reset_usage :: proc(s: ^Session) {
	s.last_usage = {}
	s.session_usage = {}
	s.subagent_total_tokens = 0
	s.usage_turns = 0
	s.peak_input_chars = 0
	s.last_input_chars = 0
	delete(s.last_stopped)
	s.last_stopped = strings.clone("")
}

session_reload_usage :: proc(s: ^Session) {
	session_reset_usage(s)
	session_overlay_usage_file(s)
}

session_overlay_usage_file :: proc(s: ^Session) {
	if len(s.session_path) == 0 {
		return
	}
	m, ok := store.load_session_metrics(s.session_path)
	if !ok {
		return
	}
	defer delete(m.model)
	defer delete(m.provider)
	s.usage_turns = m.turns
	s.session_usage.prompt_tokens = m.prompt_tokens
	s.session_usage.completion_tokens = m.completion_tokens
	s.session_usage.total_tokens = m.total_tokens
	s.session_usage.reasoning_tokens = m.reasoning_tokens
	s.session_usage.cost_usd = m.cost_usd
	s.session_usage.cost_known = m.cost_known
	s.peak_input_chars = m.peak_input_chars
	s.last_input_chars = m.last_input_chars
	s.subagent_total_tokens = m.subagent_total_tokens
}

session_new :: proc(s: ^Session, name: string) -> bool {
	want := strings.trim_space(name)
	safe: string
	if len(want) == 0 {
		safe = store.unique_session_name()
	} else {
		cand := store.sanitize_name(want)
		if s.persist && store.session_exists(cand) {
			session_set_status(s, fmt.tprintf("session %s already exists (use /resume or pick another name)", cand))
			return false
		}
		safe = strings.clone(cand)
	}
	session_maybe_persist(s)
	for m in s.messages {
		provider.destroy_message(m)
	}
	clear(&s.messages)
	delete(s.session_path)
	delete(s.name)
	s.name = safe
	s.session_path = store.named_session_path(s.name)
	session_clear_streaming(s)
	if s.persist {
		session_maybe_persist(s)
		session_set_status(s, fmt.tprintf("session %s", s.name))
	} else {
		session_set_status(s, fmt.tprintf("session %s (ephemeral)", s.name))
	}
	return true
}

session_rename :: proc(s: ^Session, name: string, force := false) -> bool {
	safe := store.sanitize_name(name)
	if safe == s.name {
		session_set_status(s, fmt.tprintf("named %s", s.name))
		return true
	}
	if !s.persist {
		delete(s.name)
		s.name = strings.clone(safe)
		delete(s.session_path)
		s.session_path = strings.clone("")
		session_set_status(s, fmt.tprintf("named %s (ephemeral)", s.name))
		return true
	}
	old_name := strings.clone(s.name)
	defer delete(old_name)
	old_path := strings.clone(s.session_path)
	defer delete(old_path)
	session_maybe_persist(s)
	had_file := len(old_path) > 0 && os.exists(old_path)
	if had_file {
		ok, err := store.rename_session_files(old_name, safe, force)
		if !ok {
			session_set_status(s, err)
			return false
		}
		store.session_unlock(old_path)
	} else if store.session_exists(safe) && !force {
		session_set_status(s, fmt.tprintf("session %s already exists", safe))
		return false
	}
	delete(s.session_path)
	delete(s.name)
	s.name = strings.clone(safe)
	s.session_path = store.named_session_path(s.name)
	session_maybe_persist(s)
	if len(s.session_path) > 0 {
		_, _ = store.session_try_lock(s.session_path)
	}
	session_set_status(s, fmt.tprintf("named %s", s.name))
	return true
}

session_switch :: proc(s: ^Session, name: string) -> bool {
	session_maybe_persist(s)
	path := store.named_session_path(store.sanitize_name(name))
	if ok, holder := store.session_try_lock(path); !ok {
		delete(path)
		session_set_status(s, fmt.tprintf("session locked by %s", holder))
		return false
	}
	if len(s.session_path) > 0 {
		store.session_unlock(s.session_path)
	}
	loaded, ok := store.load_transcript(path)
	if !ok {
		delete(path)
		delete(loaded)
		return false
	}
	for m in s.messages {
		provider.destroy_message(m)
	}
	clear(&s.messages)
	for m in loaded {
		append(&s.messages, m)
	}
	delete(loaded)
	delete(s.session_path)
	delete(s.name)
	s.session_path = path
	s.name = strings.clone(filepath.stem(path))
	delete(s.group)
	s.group = strings.clone("")
	delete(s.provider_id)
	s.provider_id = strings.clone("")
	delete(s.model)
	s.model = strings.clone("")
	session_reset_usage(s)
	session_load_meta(s)
	session_rebuild_system_prompt(s)
	session_sync_mode_env(s)
	session_clear_streaming(s)
	session_set_status(s, fmt.tprintf("resumed %s", s.name))
	return true
}

session_fork :: proc(s: ^Session, name: string, force := false) -> bool {
	new_name := store.sanitize_name(name)
	if s.persist && store.session_exists(new_name) && !force {
		session_set_status(s, fmt.tprintf("session %s already exists", new_name))
		return false
	}
	path := store.named_session_path(new_name)
	if s.persist {
		if force && store.session_exists(new_name) {
			dok, derr := store.delete_session(new_name)
			if !dok {
				delete(path)
				session_set_status(s, derr)
				return false
			}
		}
		_ = store.save_transcript(path, s.messages[:])
		_ = store.save_session_meta(path, store.Session_Meta{
			provider = s.provider_id,
			model = s.model,
			group = s.group,
			mode = agent.mode_string(s.agent_mode),
			turns = s.usage_turns,
			prompt_tokens = s.session_usage.prompt_tokens,
			completion_tokens = s.session_usage.completion_tokens,
			total_tokens = s.session_usage.total_tokens,
			reasoning_tokens = s.session_usage.reasoning_tokens,
			cost_usd = s.session_usage.cost_usd,
			cost_known = s.session_usage.cost_known,
			peak_input_chars = s.peak_input_chars,
			last_input_chars = s.last_input_chars,
			subagent_total_tokens = s.subagent_total_tokens,
		})
		usage_src := store.usage_path_for(s.session_path, context.temp_allocator)
		if os.exists(usage_src) {
			usage_dst := store.usage_path_for(path, context.temp_allocator)
			_ = store.copy_file_bytes(usage_src, usage_dst)
		}
	}
	delete(s.session_path)
	delete(s.name)
	s.session_path = path
	s.name = strings.clone(new_name)
	session_set_status(s, fmt.tprintf("forked %s", s.name))
	return true
}

session_list_text :: proc(allocator := context.allocator) -> string {
	items := store.list_sessions(allocator)
	defer store.destroy_session_infos(items, allocator)
	if len(items) == 0 {
		return strings.clone("(no sessions)", allocator)
	}
	b: strings.Builder
	strings.builder_init(&b, allocator)
	for it, i in items {
		if i > 0 {
			strings.write_string(&b, "\n")
		}
		fmt.sbprintf(&b, "%s", it.name)
		if len(it.group) > 0 {
			fmt.sbprintf(&b, " [%s]", it.group)
		}
		if len(it.model) > 0 {
			fmt.sbprintf(&b, " · %s", it.model)
		}
		fmt.sbprintf(&b, "  %s", it.preview)
	}
	return strings.to_string(b)
}

session_search_text :: proc(query: string, allocator := context.allocator) -> string {
	items := store.search_sessions(query, allocator)
	defer store.destroy_session_infos(items, allocator)
	if len(items) == 0 {
		return strings.clone("(no matches)", allocator)
	}
	b: strings.Builder
	strings.builder_init(&b, allocator)
	for it, i in items {
		if i > 0 {
			strings.write_string(&b, "\n")
		}
		fmt.sbprintf(&b, "%s", it.name)
		if len(it.group) > 0 {
			fmt.sbprintf(&b, " [%s]", it.group)
		}
		fmt.sbprintf(&b, "  %s", it.preview)
	}
	return strings.to_string(b)
}
