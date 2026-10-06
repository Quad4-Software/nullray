// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
/context token-category breakdown from the live session.
*/

package app

import "nullray:session"

slash_cmd_context :: proc(a: ^App, args: string) {
	_ = args
	text := session.context_breakdown_text(a.session, &a.tools_reg)
	session.session_push_assistant(a.session, text)
	delete(text)
	session.session_set_status(a.session, "context")
}
