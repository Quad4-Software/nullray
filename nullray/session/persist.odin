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
	})
}

session_load_meta :: proc(s: ^Session) {
	meta, ok := store.load_session_meta(s.session_path)
	if !ok {
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
}

session_new :: proc(s: ^Session, name: string) -> bool {
	session_maybe_persist(s)
	for m in s.messages {
		provider.destroy_message(m)
	}
	clear(&s.messages)
	delete(s.session_path)
	delete(s.name)
	s.name = strings.clone(store.sanitize_name(name))
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

session_rename :: proc(s: ^Session, name: string) -> bool {
	safe := store.sanitize_name(name)
	path := store.named_session_path(safe)
	session_maybe_persist(s)
	delete(s.session_path)
	delete(s.name)
	s.session_path = path
	s.name = strings.clone(safe)
	session_maybe_persist(s)
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
	session_load_meta(s)
	session_rebuild_system_prompt(s)
	session_sync_mode_env(s)
	session_clear_streaming(s)
	session_set_status(s, fmt.tprintf("resumed %s", s.name))
	return true
}

session_fork :: proc(s: ^Session, name: string) -> bool {
	new_name := store.sanitize_name(name)
	path := store.named_session_path(new_name)
	if s.persist {
		_ = store.save_transcript(path, s.messages[:])
		_ = store.save_session_meta(path, store.Session_Meta{
			provider = s.provider_id,
			model = s.model,
			group = s.group,
			mode = agent.mode_string(s.agent_mode),
		})
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
	defer store.destroy_session_infos(items)
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
	defer store.destroy_session_infos(items)
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

