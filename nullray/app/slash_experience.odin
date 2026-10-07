// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
/distill: group recorded turn entries by task signature and write the
curated experience.md digest beside the experience store.
*/

package app

import "core:fmt"
import "nullray:experience"
import "nullray:session"

slash_cmd_distill :: proc(a: ^App, args: string) {
	_ = args
	path, err := experience.exp_distill()
	if len(err) > 0 {
		session.session_set_status(a.session, fmt.tprintf("distill: %s", err))
		delete(err)
		return
	}
	msg := fmt.tprintf("experience digest written to %s", path)
	session.session_push_assistant(a.session, msg)
	delete(msg)
	session.session_set_status(a.session, "distill done")
	delete(path)
}
