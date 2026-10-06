// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Slash /todo command.
*/

package app

import "nullray:session"
import "nullray:todo"

slash_cmd_todo :: proc(a: ^App, args: string) {
	_ = args
	if !todo.enabled() {
		session.session_set_status(a.session, "todo disabled (NULLRAY_TODO=0)")
		return
	}
	view := todo.list_view(a.session.name, context.temp_allocator)
	session.session_set_status(a.session, view)
}
