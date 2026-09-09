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
	stem := "default"
	if st := sandbox.state(); st != nil && len(st.workspace) > 0 {
		base := filepath.base(st.workspace)
		if len(base) > 0 && base != "." && base != "/" {
			stem = sanitize_name(base)
		}
	}
	return resolve_named_session_path(stem, allocator)
}

named_session_path :: proc(name: string, allocator := context.allocator) -> string {
	return resolve_named_session_path(sanitize_name(name), allocator)
}

resolve_named_session_path :: proc(safe: string, allocator := context.allocator) -> string {
	ensure_session_dir()
	dir := session_dir(context.temp_allocator)
	mp, merr := filepath.join({dir, fmt.tprintf("%s.msgpack", safe)}, context.temp_allocator)
	if merr != nil {
		mp = fmt.tprintf("%s/%s.msgpack", dir, safe)
	}
	jl, jerr := filepath.join({dir, fmt.tprintf("%s.jsonl", safe)}, context.temp_allocator)
	if jerr != nil {
		jl = fmt.tprintf("%s/%s.jsonl", dir, safe)
	}
	if os.exists(mp) {
		return strings.clone(mp, allocator)
	}
	if os.exists(jl) {
		return strings.clone(jl, allocator)
	}
	return strings.clone(mp, allocator)
}

session_exists :: proc(name: string) -> bool {
	safe := sanitize_name(name)
	dir := session_dir(context.temp_allocator)
	mp := fmt.tprintf("%s/%s.msgpack", dir, safe)
	jl := fmt.tprintf("%s/%s.jsonl", dir, safe)
	return os.exists(mp) || os.exists(jl)
}

unique_session_name :: proc(allocator := context.allocator) -> string {
	base := fmt.tprintf("session-%d", time.to_unix_seconds(time.now()))
	safe := sanitize_name(base)
	if !session_exists(safe) {
		return strings.clone(safe, allocator)
	}
	for i in 1 ..= 99 {
		cand := fmt.tprintf("%s_%d", safe, i)
		if !session_exists(cand) {
			return strings.clone(cand, allocator)
		}
	}
	return strings.clone(fmt.tprintf("%s_%d", safe, os.get_pid()), allocator)
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

// Path form: contains / or \, or ends with .jsonl/.msgpack. Else treat as a session id.
looks_like_session_path :: proc(v: string) -> bool {
	if strings.has_suffix(v, ".jsonl") || strings.has_suffix(v, ".msgpack") {
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

session_file_stem :: proc(path: string, allocator := context.allocator) -> string {
	if strings.has_suffix(path, ".msgpack") {
		return strings.clone(path[:len(path) - len(".msgpack")], allocator)
	}
	if strings.has_suffix(path, ".jsonl") {
		return strings.clone(path[:len(path) - len(".jsonl")], allocator)
	}
	return strings.clone(path, allocator)
}
