// SPDX-License-Identifier: 0BSD
/*
Slash command dispatch for the TUI.
*/

package app

import "core:fmt"
import "core:strings"
import "nullray:session"

app_handle_slash :: proc(a: ^App, text: string) -> bool {
	t := strings.trim_space(text)
	if !strings.has_prefix(t, "/") {
		return false
	}
	body := t[1:]
	name := body
	args := ""
	if sp := strings.index_byte(body, ' '); sp >= 0 {
		name = body[:sp]
		args = strings.trim_space(body[sp + 1:])
	}
	if len(name) == 0 {
		return false
	}
	cmd, ok := slash_find(name)
	if !ok || cmd.run == nil {
		session.session_set_status(&a.session, fmt.tprintf("unknown command: /%s · type ?", name))
		return true
	}
	cmd.run(a, args)
	return true
}
