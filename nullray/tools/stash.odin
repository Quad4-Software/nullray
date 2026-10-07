// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
MemEx-style tool output scratchpad (Databricks blog: tool outputs live
outside the transcript, only printed slices enter context). Every large
successful tool result is auto-stashed in a per-registry in-memory store
addressed as stash-<n>; the transcript keeps a one-line stub plus a head
preview. peek pulls a line slice, stash_take returns a whole entry, and
stash_list shows what is live. The store is LRU-capped, so when an entry
drops the transcript stub is all that remains.

State rides on the Registry like script_tools: stash tools bind their
store through Tool.user. The mutex covers speculate worker threads.
*/

package tools

import "core:fmt"
import "core:mem"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:sync"

STASH_STUB_PREFIX :: "stashed as "
STASH_MAX_ENTRIES :: 64
STASH_MIN_CHARS_DEFAULT :: 800
STASH_PREVIEW_CHARS :: 120
STASH_PEEK_LINES_DEFAULT :: 200
STASH_PEEK_BYTES_MAX :: 32_768

ENV_STASH :: "NULLRAY_STASH"
ENV_STASH_MIN :: "NULLRAY_STASH_MIN_CHARS"

Stash_Entry :: struct {
	id:      string,
	body:    string,
	preview: string, // one-line summary for stash_list
	tick:    u64,    // LRU clock
}

Stash :: struct {
	mu:      sync.Mutex,
	entries: [dynamic]Stash_Entry,
	alloc:   mem.Allocator,
	next_id: int,
	tick:    u64,
	saved:   int, // total body bytes diverted into stubs
}

stash_init :: proc(s: ^Stash, allocator := context.allocator) {
	s^ = {}
	s.entries = make([dynamic]Stash_Entry, allocator)
	s.alloc = allocator
	s.next_id = 1
}

stash_destroy :: proc(s: ^Stash) {
	if s == nil {
		return
	}
	for &e in s.entries {
		delete(e.id, s.alloc)
		delete(e.body, s.alloc)
		delete(e.preview, s.alloc)
	}
	delete(s.entries)
	s^ = {}
}

// NULLRAY_STASH=0 disables. Default on.
stash_enabled :: proc() -> bool {
	if v, ok := os.lookup_env(ENV_STASH, context.temp_allocator); ok {
		switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
		case "0", "false", "no", "off":
			return false
		}
	}
	return true
}

stash_min_chars :: proc() -> int {
	if v, ok := os.lookup_env(ENV_STASH_MIN, context.temp_allocator); ok {
		if n, n_ok := strconv.parse_int(strings.trim_space(v)); n_ok && n > 0 {
			return n
		}
	}
	return STASH_MIN_CHARS_DEFAULT
}

stash_reader_name :: proc(name: string) -> bool {
	return name == "peek" || name == "stash_take" || name == "stash_list"
}

// Caller holds s.mu. Lazy-init covers zero-value registries built without
// registry_init (a nil dynamic array means nothing was ever stashed).
stash_ensure_locked :: proc(s: ^Stash) {
	if s.entries == nil {
		s.entries = make([dynamic]Stash_Entry)
		s.alloc = context.allocator
	}
	if s.next_id < 1 {
		s.next_id = 1
	}
}

stash_first_line :: proc(body: string) -> string {
	line := body
	if nl := strings.index_byte(line, '\n'); nl >= 0 {
		line = line[:nl]
	}
	line = strings.trim_right_space(line)
	if len(line) > 80 {
		line = line[:80]
	}
	return line
}

count_result_lines :: proc(s: string) -> int {
	if len(s) == 0 {
		return 0
	}
	n := 1
	for c in s {
		if c == '\n' {
			n += 1
		}
	}
	return n
}

// Caller holds s.mu. Returns the new id on the temp allocator: the entry
// keeps its own clone so the caller never frees into the store.
stash_put_locked :: proc(s: ^Stash, body: string) -> string {
	stash_ensure_locked(s)
	s.tick += 1
	id := fmt.tprintf("stash-%d", s.next_id)
	s.next_id += 1
	append(&s.entries, Stash_Entry{
		id = strings.clone(id, s.alloc),
		body = strings.clone(body, s.alloc),
		preview = strings.clone(stash_first_line(body), s.alloc),
		tick = s.tick,
	})
	for len(s.entries) > STASH_MAX_ENTRIES {
		stash_evict_lru_locked(s)
	}
	return id
}

stash_evict_lru_locked :: proc(s: ^Stash) {
	if len(s.entries) == 0 {
		return
	}
	oldest := 0
	for e, i in s.entries {
		if e.tick < s.entries[oldest].tick {
			oldest = i
		}
	}
	victim := s.entries[oldest]
	delete(victim.id, s.alloc)
	delete(victim.body, s.alloc)
	delete(victim.preview, s.alloc)
	ordered_remove(&s.entries, oldest)
}

// Caller holds s.mu. A hit refreshes the LRU clock.
stash_find_locked :: proc(s: ^Stash, id: string) -> ^Stash_Entry {
	for &e in s.entries {
		if e.id == id {
			s.tick += 1
			e.tick = s.tick
			return &e
		}
	}
	return nil
}

stash_latest_locked :: proc(s: ^Stash) -> ^Stash_Entry {
	latest: ^Stash_Entry
	for &e in s.entries {
		if latest == nil || e.tick > latest.tick {
			latest = &e
		}
	}
	return latest
}

/*
Replace an oversized successful result with a stub plus head preview; the
full body lands in the registry stash store. Returns the input string
with stashed=false when the feature is off, the body is small, or the
tool is one of the stash readers (their output must reach the model).
The caller frees the original string when stashed=true.
*/
stash_result :: proc(
	r: ^Registry,
	name: string,
	result: string,
	allocator := context.allocator,
) -> (out: string, stashed: bool) {
	if r == nil || !stash_enabled() || stash_reader_name(name) {
		return result, false
	}
	if len(result) <= stash_min_chars() {
		return result, false
	}
	sync.mutex_lock(&r.stash.mu)
	id := stash_put_locked(&r.stash, result)
	r.stash.saved += len(result)
	sync.mutex_unlock(&r.stash.mu)
	pn := min(STASH_PREVIEW_CHARS, len(result))
	preview := result[:pn]
	lines := 1
	for c in preview {
		if c == '\n' {
			lines += 1
		}
	}
	out = fmt.aprintf(
		"%s%s, %d bytes, %d lines total; lines 1-%d preview (peek for slices, stash_take for full)\n%s",
		STASH_STUB_PREFIX,
		id,
		len(result),
		count_result_lines(result),
		lines,
		preview,
		allocator = allocator,
	)
	return out, true
}

/*
Parse the byte count out of a stash stub ("stashed as stash-3, 5021
bytes, ...") for harness metrics. ok=false for non-stub text.
*/
stash_saved_bytes :: proc(s: string) -> (n: int, ok: bool) {
	idx := strings.index(s, STASH_STUB_PREFIX)
	if idx < 0 {
		return 0, false
	}
	rest := s[idx + len(STASH_STUB_PREFIX):]
	comma := strings.index_byte(rest, ',')
	if comma < 0 {
		return 0, false
	}
	rest = strings.trim_left_space(rest[comma + 1:])
	end := 0
	for end < len(rest) && rest[end] >= '0' && rest[end] <= '9' {
		end += 1
	}
	if end == 0 || !strings.has_prefix(rest[end:], " bytes") {
		return 0, false
	}
	return strconv.parse_int(rest[:end])
}

stash_tool_peek :: proc(
	user: rawptr,
	name: string,
	args_json: string,
	allocator := context.allocator,
) -> (result: string, err: string) {
	s := cast(^Stash)user
	if s == nil {
		return "", strings.clone("stash store unavailable", allocator)
	}
	id, ierr := json_arg_string(args_json, "id", allocator)
	if len(ierr) > 0 {
		return "", ierr
	}
	defer delete(id)
	offset_s, _ := json_arg_string_optional(args_json, "offset", "", context.temp_allocator)
	limit_s, _ := json_arg_string_optional(args_json, "limit", "", context.temp_allocator)
	offset := 1
	limit := STASH_PEEK_LINES_DEFAULT
	if n, ok := parse_positive_int(offset_s); ok && n > 0 {
		offset = n
	}
	if len(strings.trim_space(limit_s)) > 0 {
		if n, ok := parse_positive_int(limit_s); ok {
			limit = n
		}
	}
	sync.mutex_lock(&s.mu)
	defer sync.mutex_unlock(&s.mu)
	e := stash_find_locked(s, id)
	if e == nil {
		return "", fmt.aprintf("unknown stash id: %s", id, allocator = allocator)
	}
	lines := strings.split_lines(e.body, context.temp_allocator)
	start := clamp(offset - 1, 0, len(lines))
	end := len(lines)
	if limit > 0 && start + limit < end {
		end = start + limit
	}
	b: strings.Builder
	strings.builder_init(&b, allocator)
	fmt.sbprintf(&b, "stash=%s lines=%d..%d of %d\n", id, start + 1, end, len(lines))
	used := 0
	for i in start ..< end {
		line := lines[i]
		need := len(line) + 1
		if used + need > STASH_PEEK_BYTES_MAX {
			strings.write_string(&b, "... truncated (byte cap)\n")
			break
		}
		strings.write_string(&b, line)
		used += len(line)
		if i + 1 < end {
			strings.write_byte(&b, '\n')
			used += 1
		}
	}
	return strings.to_string(b), ""
}

stash_tool_take :: proc(
	user: rawptr,
	name: string,
	args_json: string,
	allocator := context.allocator,
) -> (result: string, err: string) {
	s := cast(^Stash)user
	if s == nil {
		return "", strings.clone("stash store unavailable", allocator)
	}
	id, _ := json_arg_string_optional(args_json, "id", "", context.temp_allocator)
	sync.mutex_lock(&s.mu)
	defer sync.mutex_unlock(&s.mu)
	e: ^Stash_Entry
	if len(strings.trim_space(id)) > 0 {
		e = stash_find_locked(s, id)
		if e == nil {
			return "", fmt.aprintf("unknown stash id: %s", id, allocator = allocator)
		}
	} else {
		e = stash_latest_locked(s)
		if e == nil {
			return "", strings.clone("no stashed results", allocator)
		}
	}
	return fmt.aprintf("stash=%s %d bytes\n%s", e.id, len(e.body), e.body, allocator = allocator), ""
}

stash_tool_list :: proc(
	user: rawptr,
	name: string,
	args_json: string,
	allocator := context.allocator,
) -> (result: string, err: string) {
	s := cast(^Stash)user
	if s == nil {
		return "", strings.clone("stash store unavailable", allocator)
	}
	sync.mutex_lock(&s.mu)
	defer sync.mutex_unlock(&s.mu)
	if len(s.entries) == 0 {
		return strings.clone("no stashed results", allocator), ""
	}
	b: strings.Builder
	strings.builder_init(&b, allocator)
	for e in s.entries {
		fmt.sbprintf(&b, "%s %d bytes  %s\n", e.id, len(e.body), e.preview)
	}
	return strings.to_string(b), ""
}

register_stash_tools :: proc(r: ^Registry) {
	if r == nil {
		return
	}
	registry_register(r, Tool{
		name = "peek",
		description = "Read a line slice of a stashed tool result by id (ids come from stashed-as stubs or stash_list)",
		schema_json = `{"type":"object","properties":{"id":{"type":"string"},"offset":{"type":"string","description":"1-based start line"},"limit":{"type":"string","description":"max lines to return"}},"required":["id"]}`,
		kind = .Read,
		run_named = stash_tool_peek,
		user = &r.stash,
	})
	registry_register(r, Tool{
		name = "stash_take",
		description = "Return the full body of a stashed tool result by id, or the most recent stash when id is omitted",
		schema_json = `{"type":"object","properties":{"id":{"type":"string"}}}`,
		kind = .Read,
		run_named = stash_tool_take,
		user = &r.stash,
	})
	registry_register(r, Tool{
		name = "stash_list",
		description = "List live stashed tool results: id, size, one-line preview",
		schema_json = `{"type":"object","properties":{}}`,
		kind = .Read,
		run_named = stash_tool_list,
		user = &r.stash,
	})
}
