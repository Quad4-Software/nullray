// SPDX-License-Identifier: 0BSD
/*
Session path helpers under the config directory.
*/

package store

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"
import "nullray:sandbox"

session_dir :: proc(allocator := context.allocator) -> string {
	base := sandbox.resolve_config_dir(context.temp_allocator)
	joined, err := filepath.join({base, "sessions"}, allocator)
	if err != nil {
		return fmt.aprintf("%s/sessions", base, allocator = allocator)
	}
	return joined
}

ensure_session_dir :: proc() -> bool {
	dir := session_dir(context.temp_allocator)
	_ = os.make_directory_all(dir)
	return true
}

default_session_path :: proc(allocator := context.allocator) -> string {
	ensure_session_dir()
	dir := session_dir(context.temp_allocator)
	st := sandbox.state()
	name := "default.jsonl"
	if st != nil && len(st.workspace) > 0 {
		base := filepath.base(st.workspace)
		if len(base) > 0 && base != "." && base != "/" {
			name = fmt.tprintf("%s.jsonl", sanitize_name(base))
		}
	}
	joined, err := filepath.join({dir, name}, allocator)
	if err != nil {
		return fmt.aprintf("%s/%s", dir, name, allocator = allocator)
	}
	return joined
}

named_session_path :: proc(name: string, allocator := context.allocator) -> string {
	ensure_session_dir()
	dir := session_dir(context.temp_allocator)
	safe := sanitize_name(name)
	file := fmt.tprintf("%s.jsonl", safe)
	joined, err := filepath.join({dir, file}, allocator)
	if err != nil {
		return fmt.aprintf("%s/%s", dir, file, allocator = allocator)
	}
	return joined
}

sanitize_name :: proc(s: string) -> string {
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	for r in s {
		switch r {
		case 'a' ..= 'z', 'A' ..= 'Z', '0' ..= '9', '-', '_':
			strings.write_rune(&b, r)
		case:
			strings.write_rune(&b, '_')
		}
	}
	out := strings.to_string(b)
	if len(out) == 0 {
		return "default"
	}
	return out
}

// Path form: contains / or \, or ends with .jsonl. Else treat as a session id.
looks_like_session_path :: proc(v: string) -> bool {
	if strings.has_suffix(v, ".jsonl") {
		return true
	}
	for c in v {
		if c == '/' || c == '\\' {
			return true
		}
	}
	return false
}

store_sanitize_group :: proc(s: string) -> string {
	return sanitize_name(s)
}


