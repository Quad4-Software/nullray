// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Frame tick: dirty flag, banner refresh, modal polls, busy reveal cadence.
*/

package app

import "core:fmt"
import "core:time"
import "nullray:constants"
import "nullray:provider"
import "nullray:sandbox"
import "nullray:session"
import "nullray:store"
import "nullray:subagent"
import "nullray:ui"

app_tui_apply :: proc(theme: ui.Theme, persistent: bool, user: rawptr) {
	a := cast(^App)user
	_ = persistent
	if a == nil {
		return
	}
	ui.theme_set(theme)
	if a.loop != nil {
		a.loop.theme = theme
		ui.loop_request_full_redraw(a.loop)
	}
	app_mark_dirty(a)
}

app_mark_dirty :: proc(a: ^App) {
	a.dirty = true
}

BANNER_REFRESH_MS :: 2000

app_refresh_banner :: proc(a: ^App) {
	cfg_dir := sandbox.resolve_config_dir(context.temp_allocator)
	a.banner_live = session.count_live_agents(cfg_dir)
	items := store.list_sessions(context.temp_allocator)
	a.banner_sess = len(items)
	store.destroy_session_infos(items, context.temp_allocator)
	a.banner_refresh = time.tick_now()
}

app_is_dirty :: proc(user: rawptr) -> bool {
	a := cast(^App)user
	// Keep dirty sources minimal: avoid full redraws when nothing moved.
	return a.dirty ||
		splash_active(a) ||
		a.show_setup ||
		a.elevate_active ||
		a.ask_active ||
		a.view_form_active ||
		a.show_status ||
		len(a.toasts) > 0 ||
		a.sel_dragging
}


app_on_tick :: proc(user: rawptr) -> bool {
	a := cast(^App)user
	changed := false
	if app_elevate_poll(a) {
		changed = true
	}
	// Unified poll covers classic ask_question and show_view forms.
	if app_ask_poll_views(a) {
		changed = true
	}
	if app_toasts_expire(a) {
		changed = true
	}
	if splash_active(a) {
		changed = true
		app_mark_dirty(a)
	}
	if time.tick_diff(a.banner_refresh, time.tick_now()) >= time.Duration(BANNER_REFRESH_MS) * time.Millisecond {
		prev_s, prev_l := a.banner_sess, a.banner_live
		app_refresh_banner(a)
		if a.banner_sess != prev_s || a.banner_live != prev_l {
			changed = true
		}
	}
	was_busy := a.session.busy
	if session.session_tick_status_hold(a.session) {
		changed = true
	}
	if app_apply_improve_pending(a) {
		changed = true
	}
	if app_apply_models_pending(a) {
		changed = true
	}
	// Runs before app_poll_tabs so finished heartbeat turns are unmarked
	// before the busy-to-idle notification sees them.
	if schedule_tick_poll(a) {
		changed = true
	}
	poll_changed := app_poll_tabs(a)
	changed = poll_changed || changed
	if app_reveal_tick(a) {
		changed = true
	}
	if was_busy && !a.session.busy {
		app_reveal_reset(a)
		app_refresh_credits(a)
		changed = true
		if a.follow {
			a.scroll = 0
		}
		if follow := session.session_take_followup(a.session); len(follow) > 0 {
			session.session_push_user(a.session, follow)
			delete(follow)
			p := provider.registry_active(&a.registry)
			session.session_start_chat(a.session, p)
			app_toast(a, "queued follow-up", .Info)
		}
		if a.view_auto {
			paths := collect_turn_write_paths(a.session.messages[:], context.allocator)
			if len(paths) > 0 {
				app_view_set_recent(a, paths)
				last := paths[len(paths) - 1]
				if app_view_open(a, last) {
					a.view_focus = false
					base := last
					app_toast(a, fmt.tprintf("opened %s", base), .Info)
				}
				destroy_write_paths(paths)
				changed = true
			} else {
				destroy_write_paths(paths)
			}
		}
	}
	// Redraw on new deltas, or on spinner/caret/reveal cadence while busy.
	// Avoid full transcript layout every poll tick with no UI change.
	living_agents := subagent.roster_living_children(&a.subagents.roster)
	if app_tabs_any_busy(a) || a.session.has_streaming || a.session.has_thinking || len(a.session.pending_status) > 0 || living_agents > 0 {
		anim_due := time.tick_diff(a.anim_tick, time.tick_now()) >=
			time.Duration(constants.SPINNER_FRAME_MS) * time.Millisecond
		if poll_changed || anim_due {
			a.anim_tick = time.tick_now()
			changed = true
			if a.follow {
				a.scroll = 0
			}
		}
	}
	if changed {
		app_mark_dirty(a)
	}
	return changed
}
