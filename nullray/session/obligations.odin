// SPDX-License-Identifier: 0BSD
/*
Regression obligations: re-run prior green verifies later in the session.
*/

package session

import "core:strings"

session_add_verify_obligation :: proc(s: ^Session, cmd: string) {
	if s == nil || len(strings.trim_space(cmd)) == 0 {
		return
	}
	for existing in s.verify_obligations {
		if existing == cmd {
			return
		}
	}
	append(&s.verify_obligations, strings.clone(cmd))
}

session_clear_verify_obligations :: proc(s: ^Session) {
	if s == nil {
		return
	}
	for c in s.verify_obligations {
		delete(c)
	}
	clear(&s.verify_obligations)
}
