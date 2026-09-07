// SPDX-License-Identifier: 0BSD
/*
Session-scoped shared knowledge store with authorship.
*/

package subagent

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:sync"
import "core:time"
import "nullray:constants"
import "nullray:sandbox"

Knowledge_Entry :: struct {
	key:        string,
	value:      string,
	author_id:  string,
	tags:       [dynamic]string,
	updated_at: i64,
}

Knowledge_Store :: struct {
	mu:       sync.Mutex,
	entries:  map[string]Knowledge_Entry,
	session:  string,
	dir:      string,
}

knowledge_init :: proc(k: ^Knowledge_Store, session_id: string) {
	k^ = {}
	k.entries = make(map[string]Knowledge_Entry)
	k.session = strings.clone(session_id)
	ws := workspace_dir()
	k.dir, _ = filepath.join({ws, constants.KNOWLEDGE_DIR, session_id})
	_ = os.make_directory_all(k.dir)
}

knowledge_destroy :: proc(k: ^Knowledge_Store) {
	if k == nil {
		return
	}
	sync.mutex_lock(&k.mu)
	for key, &e in k.entries {
		delete(e.key)
		delete(e.value)
		delete(e.author_id)
		for t in e.tags {
			delete(t)
		}
		delete(e.tags)
		delete(key)
	}
	delete(k.entries)
	delete(k.session)
	delete(k.dir)
	sync.mutex_unlock(&k.mu)
	k^ = {}
}

workspace_dir :: proc(allocator := context.temp_allocator) -> string {
	st := sandbox.state()
	if st != nil && len(st.workspace) > 0 {
		return st.workspace
	}
	if cwd, err := os.get_working_directory(allocator); err == nil {
		return cwd
	}
	return "."
}

looks_like_secret :: proc(value: string) -> bool {
	low := strings.to_lower(value, context.temp_allocator)
	if strings.contains(low, "api_key") || strings.contains(low, "secret=") || strings.contains(low, "password=") {
		return true
	}
	if strings.has_prefix(strings.trim_space(value), "sk-") {
		return true
	}
	return false
}

knowledge_put :: proc(
	k: ^Knowledge_Store,
	key: string,
	value: string,
	author_id: string,
	tags: []string,
	allocator := context.allocator,
) -> (err: string) {
	if k == nil {
		return strings.clone("no knowledge store", allocator)
	}
	key_trim := strings.trim_space(key)
	if len(key_trim) == 0 {
		return strings.clone("empty knowledge key", allocator)
	}
	if looks_like_secret(value) {
		return strings.clone("refusing to store secret-shaped knowledge value", allocator)
	}
	val := value
	if len(val) > constants.MAX_KNOWLEDGE_VALUE_CHARS {
		val = val[:constants.MAX_KNOWLEDGE_VALUE_CHARS]
	}
	sync.mutex_lock(&k.mu)
	defer sync.mutex_unlock(&k.mu)
	if len(k.entries) >= constants.MAX_KNOWLEDGE_ENTRIES {
		if _, exists := k.entries[key_trim]; !exists {
			return strings.clone("knowledge store full", allocator)
		}
	}
	if old, ok := k.entries[key_trim]; ok {
		delete(old.key)
		delete(old.value)
		delete(old.author_id)
		for t in old.tags {
			delete(t)
		}
		delete(old.tags)
		delete_key(&k.entries, key_trim)
	}
	e := Knowledge_Entry{
		key = strings.clone(key_trim),
		value = strings.clone(val),
		author_id = strings.clone(author_id),
		tags = make([dynamic]string),
		updated_at = time.time_to_unix(time.now()),
	}
	for t in tags {
		append(&e.tags, strings.clone(t))
	}
	k.entries[strings.clone(key_trim)] = e
	_ = knowledge_append_jsonl(k, e)
	return ""
}

knowledge_append_jsonl :: proc(k: ^Knowledge_Store, e: Knowledge_Entry) -> bool {
	if len(k.dir) == 0 {
		return false
	}
	path, _ := filepath.join({k.dir, "knowledge.jsonl"}, context.temp_allocator)
	line := fmt.tprintf(
		`{{"key":%q,"author":%q,"updated":%d,"value":%q}}`+"\n",
		e.key,
		e.author_id,
		e.updated_at,
		e.value,
	)
	f, err := os.open(path, os.O_WRONLY | os.O_CREATE | os.O_APPEND)
	if err != nil {
		return false
	}
	defer os.close(f)
	_, werr := os.write_string(f, line)
	return werr == nil
}

knowledge_get :: proc(k: ^Knowledge_Store, key: string, allocator := context.allocator) -> (text: string, err: string) {
	if k == nil {
		return "", strings.clone("no knowledge store", allocator)
	}
	sync.mutex_lock(&k.mu)
	defer sync.mutex_unlock(&k.mu)
	e, ok := k.entries[key]
	if !ok {
		return "", fmt.aprintf("unknown key: %s", key, allocator = allocator)
	}
	return fmt.aprintf("%s\n(author=%s)", e.value, e.author_id, allocator = allocator), ""
}

knowledge_list :: proc(k: ^Knowledge_Store, filter: string, allocator := context.allocator) -> string {
	if k == nil {
		return strings.clone("(no knowledge store)", allocator)
	}
	sync.mutex_lock(&k.mu)
	defer sync.mutex_unlock(&k.mu)
	b: strings.Builder
	strings.builder_init(&b, allocator)
	author_filter := ""
	tag_filter := ""
	if strings.has_prefix(filter, "author:") {
		author_filter = filter[7:]
	} else if len(filter) > 0 {
		tag_filter = filter
	}
	n := 0
	for _, e in k.entries {
		if len(author_filter) > 0 && e.author_id != author_filter {
			continue
		}
		if len(tag_filter) > 0 {
			hit := false
			for t in e.tags {
				if t == tag_filter {
					hit = true
					break
				}
			}
			if !hit && !strings.contains(e.key, tag_filter) {
				continue
			}
		}
		fmt.sbprintf(&b, "%s author=%s\n", e.key, e.author_id)
		n += 1
	}
	if n == 0 {
		strings.write_string(&b, "(empty)")
	}
	return strings.to_string(b)
}

knowledge_digest :: proc(k: ^Knowledge_Store, max_chars: int, allocator := context.allocator) -> string {
	if k == nil {
		return strings.clone("", allocator)
	}
	sync.mutex_lock(&k.mu)
	defer sync.mutex_unlock(&k.mu)
	b: strings.Builder
	strings.builder_init(&b, allocator)
	for _, e in k.entries {
		line := fmt.tprintf("- %s: %s\n", e.key, e.value)
		if len(line) > 120 {
			line = fmt.tprintf("- %s: %s...\n", e.key, e.value[:min(80, len(e.value))])
		}
		if strings.builder_len(b) + len(line) > max_chars {
			break
		}
		strings.write_string(&b, line)
	}
	return strings.to_string(b)
}

knowledge_conflicts_text :: proc(k: ^Knowledge_Store, allocator := context.allocator) -> string {
	// Last-write-wins store has one value per key. Conflicts are tracked via jsonl history later.
	return strings.clone("", allocator)
}

knowledge_clear :: proc(k: ^Knowledge_Store) {
	if k == nil {
		return
	}
	sync.mutex_lock(&k.mu)
	for key, &e in k.entries {
		delete(e.key)
		delete(e.value)
		delete(e.author_id)
		for t in e.tags {
			delete(t)
		}
		delete(e.tags)
		delete(key)
	}
	clear(&k.entries)
	sync.mutex_unlock(&k.mu)
}
