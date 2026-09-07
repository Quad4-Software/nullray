// SPDX-License-Identifier: 0BSD
/*
Frame loop: resize, dirty clear/draw/present, poll input, session_poll.
*/

package ui

import "nullray:constants"

Loop :: struct {
	term:       Term,
	buf:        Buffer,
	quit:       bool,
	force_full: bool,
	theme:      Theme,
}

Draw_Proc :: #type proc(buf: ^Buffer, user: rawptr)
Event_Proc :: #type proc(ev: Event, user: rawptr) -> (quit: bool)
Dirty_Proc :: #type proc(user: rawptr) -> bool
Tick_Proc :: #type proc(user: rawptr) -> (dirty: bool)

loop_init :: proc(l: ^Loop, preferred_color := "", theme_name := "") -> bool {
	l^ = {}
	l.theme = theme_by_name(theme_name)
	theme_set(l.theme)
	if !term_init(&l.term, preferred_color) {
		return false
	}
	l.buf = buffer_create(l.term.width, l.term.height)
	return true
}

loop_close :: proc(l: ^Loop) {
	buffer_destroy(&l.buf)
	term_close(&l.term)
}

loop_request_full_redraw :: proc(l: ^Loop) {
	l.force_full = true
}

loop_run :: proc(
	l: ^Loop,
	draw: Draw_Proc,
	on_event: Event_Proc,
	user: rawptr,
	is_dirty: Dirty_Proc = nil,
	on_tick: Tick_Proc = nil,
) {
	force := true
	for !l.quit {
		free_all(context.temp_allocator)

		term_query_size(&l.term)
		if l.buf.width != l.term.width || l.buf.height != l.term.height {
			buffer_resize(&l.buf, l.term.width, l.term.height)
			force = true
		}
		if l.force_full {
			force = true
			term_invalidate(&l.term)
			l.force_full = false
		}

		dirty := force
		if !dirty && is_dirty != nil {
			dirty = is_dirty(user)
		}

		if dirty {
			t := l.theme
			buffer_clear(&l.buf, t.bg, t.fg)
			if draw != nil {
				draw(&l.buf, user)
			}
			term_present(&l.term, &l.buf)
			force = false
		}

		ev, ok := poll_event(constants.POLL_TIMEOUT_MS)
		for ok {
			if ev.kind == .Ctrl_C || ev.kind == .Ctrl_Q {
				l.quit = true
				break
			}
			if on_event != nil && on_event(ev, user) {
				l.quit = true
				break
			}
			// Drain queued input without blocking so wheel/keys feel snappy
			ev, ok = poll_event(0)
		}

		if on_tick != nil {
			if on_tick(user) {
				force = true
			}
		}
	}
}
