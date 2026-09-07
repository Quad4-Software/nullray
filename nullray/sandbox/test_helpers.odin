// SPDX-License-Identifier: 0BSD
package sandbox

import "core:os"
import "core:strings"

/*
Save then restore one env key around a test mutation.
*/
@(private)
test_env_set :: proc(key, value: string) -> (had: bool, prev: string) {
	if v, ok := os.lookup_env(key, context.allocator); ok {
		had = true
		prev = v
	}
	os.set_env(key, value)
	return
}

@(private)
test_env_restore :: proc(key: string, had: bool, prev: string) {
	if had {
		os.set_env(key, prev)
		delete(prev)
	} else {
		os.unset_env(key)
	}
}

@(private)
test_env_unset :: proc(key: string) -> (had: bool, prev: string) {
	if v, ok := os.lookup_env(key, context.allocator); ok {
		had = true
		prev = v
		os.unset_env(key)
		return
	}
	return false, ""
}

@(private)
test_state_with_allows :: proc(rw, ro: []string, applied: bool) -> State {
	s: State
	s.applied = applied
	s.mode = .Warn
	s.fs = .RW
	s.allow_rw = make([dynamic]string)
	s.allow_ro = make([dynamic]string)
	for p in rw {
		append(&s.allow_rw, strings.clone(p))
	}
	for p in ro {
		append(&s.allow_ro, strings.clone(p))
	}
	return s
}
