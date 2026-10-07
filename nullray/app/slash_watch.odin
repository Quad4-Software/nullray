// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
/watch slash command: same standing-watch surface as the CLI, scoped to
the current session so wakeups land back in this tab.
*/

package app

import "core:strconv"
import "core:strings"
import "nullray:schedule"
import "nullray:session"

slash_cmd_watch :: proc(a: ^App, args: string) {
	if !schedule.schedule_enabled() {
		session.session_set_status(a.session, "schedule off (NULLRAY_SCHEDULE=0)")
		return
	}
	parts := strings.fields(strings.trim_space(args), context.temp_allocator)
	if len(parts) == 0 || parts[0] == "list" || parts[0] == "status" {
		session.session_set_status(a.session, schedule.watch_list_text(schedule.unix_now(), context.temp_allocator))
		return
	}
	if parts[0] == "rm" || parts[0] == "cancel" {
		if len(parts) < 2 {
			session.session_set_status(a.session, "usage: /watch rm ID")
			return
		}
		n, ok := strconv.parse_int(parts[1])
		if !ok || !schedule.watch_rm(n) {
			session.session_set_status(a.session, "no such watch")
			return
		}
		session.session_set_status(a.session, "watch removed")
		return
	}
	if parts[0] == "show" {
		if len(parts) < 2 {
			session.session_set_status(a.session, "usage: /watch show ID")
			return
		}
		n, ok := strconv.parse_int(parts[1])
		if !ok {
			session.session_set_status(a.session, "usage: /watch show ID")
			return
		}
		session.session_set_status(a.session, schedule.watch_show_text(n, context.temp_allocator))
		return
	}
	if parts[0] == "add" {
		spec, rest, serr := schedule.watch_spec_parse(parts[1:], context.temp_allocator)
		if len(serr) > 0 {
			defer delete(serr)
			session.session_set_status(a.session, serr)
			return
		}
		if len(rest) == 0 {
			session.session_set_status(a.session, "usage: /watch add 2h|\"every 2h\"|cron5 <instruction>")
			return
		}
		prompt := strings.join(rest, " ", context.temp_allocator)
		now := schedule.unix_now()
		id, aerr := schedule.watch_add(prompt, spec, a.session.name, 0, 0, 0, now)
		if len(aerr) > 0 {
			defer delete(aerr)
			session.session_set_status(a.session, aerr)
			return
		}
		in_sec, _ := schedule.job_next_fire_in(id, now)
		session.session_set_status(
			a.session,
			strings.concatenate(
				{"watch added, next fire in ", schedule.fmt_delta(in_sec, context.temp_allocator)},
				context.temp_allocator,
			),
		)
		return
	}
	session.session_set_status(a.session, "usage: /watch [list|status|add <spec> <instruction>|show ID|rm ID]")
}
