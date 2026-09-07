// SPDX-License-Identifier: 0BSD
/*
App shell: lifecycle, credits, dirty flag, tick.
*/

package app

import "core:fmt"
import "core:os"
import "core:strings"
import "core:thread"
import "core:time"
import "nullray:agent"
import "nullray:config"
import "nullray:constants"
import "nullray:mcp"
import "nullray:provider"
import "nullray:sandbox"
import "nullray:session"
import "nullray:store"
import "nullray:tools"
import "nullray:ui"

App :: struct {
	loop:           ^ui.Loop,
	registry:       provider.Registry,
	tools_reg:      tools.Registry,
	mcp_reg:        mcp.Registry,
	session:        session.Session,
	input:          strings.Builder,
	cursor:         int,
	dirty:          bool,
	spinner:        ui.Spinner,
	scroll:         int,
	follow:         bool,
	credits_label:  string,
	show_help:      bool,
	help_scroll:    int,
	suggest_sel:    int,
	binds:          config.Binds,
	keys_preset:    config.Key_Preset,
	help_btn_x:     int,
	improve_undo:   string,
	improving:      bool,
	pasting:        bool,
	credits_busy:   bool,
	splash_on:      bool,
	splash_start:   time.Tick,
	banner_sess:    int,
	banner_live:    int,
	banner_refresh: time.Tick,
	anim_tick:      time.Tick,
}

app_init :: proc(a: ^App, loop: ^ui.Loop) {
	a^ = {}
	a.loop = loop
	tools.registry_init(&a.tools_reg)
	mcp.registry_init(&a.mcp_reg, &a.tools_reg)
	mcp.mcp_autoload(&a.mcp_reg)
	provider.registry_init(&a.registry)
	session.session_init(&a.session)
	a.session.tools_registry = &a.tools_reg
	session.session_rebuild_system_prompt(&a.session)
	_ = session.session_apply_saved_model(&a.session, &a.registry)
	strings.builder_init(&a.input)
	a.spinner = ui.spinner_init()
	a.dirty = true
	a.follow = true
	a.splash_on = splash_enabled_from_env()
	a.splash_start = time.tick_now()
	a.binds, a.keys_preset = config.load_binds()
	_ = config.write_default_keys_file()
	app_refresh_banner(a)
	agent.apply_auto_mode()
	if agent.auto_from_env() {
		a.session.agent_mode = .Edit
		session.session_sync_mode_env(&a.session)
		session.session_rebuild_system_prompt(&a.session)
	}
	app_refresh_credits(a)

	cfg_dir := sandbox.resolve_config_dir(context.temp_allocator)
	if sid, recovered := session.crash_lock_recover(cfg_dir); recovered {
		if session.session_switch(&a.session, sid) {
			_ = session.session_apply_saved_model(&a.session, &a.registry)
			session.session_set_status(&a.session, fmt.tprintf("recovered session %s after crash", sid))
		}
		delete(sid)
		session.crash_lock_clear(cfg_dir)
	}
	session.crash_lock_write(cfg_dir, a.session.name)

	p := provider.registry_active(&a.registry)
	if p != nil {
		tools_label := "tools"
		if !a.session.tools_enabled {
			tools_label = "chat"
		}
		status := fmt.tprintf(
			"%s / %s / %s / %s / %s",
			p.name,
			p.default_model,
			tools_label,
			agent.mode_string(a.session.agent_mode),
			tools.perms_string(tools.perms_from_env()),
		)
		if p.id == "openrouter" && len(p.api_key) == 0 {
			status = "error: OPENROUTER_API_KEY missing in ~/.config/nullray/env"
		} else if len(a.credits_label) > 0 {
			status = fmt.tprintf("%s · %s", status, a.credits_label)
		}
		session.session_set_status(&a.session, status)
	}
}

app_destroy :: proc(a: ^App) {
	cfg_dir := sandbox.resolve_config_dir(context.temp_allocator)
	session.crash_lock_clear(cfg_dir)
	provider.registry_destroy(&a.registry)
	session.session_destroy(&a.session)
	mcp.registry_destroy(&a.mcp_reg)
	tools.registry_destroy(&a.tools_reg)
	strings.builder_destroy(&a.input)
	delete(a.credits_label)
	delete(a.improve_undo)
}

app_refresh_credits :: proc(a: ^App) {
	if a.credits_busy {
		return
	}
	p := provider.registry_active(&a.registry)
	if p == nil || p.id != "openrouter" || len(p.api_key) == 0 {
		delete(a.credits_label)
		a.credits_label = ""
		return
	}
	a.credits_busy = true
	args := new(Credits_Job)
	args.app = a
	args.api_key = strings.clone(p.api_key)
	thread.run_with_data(args, credits_job)
}

Credits_Job :: struct {
	app:     ^App,
	api_key: string,
}

@(private)
credits_job :: proc(data: rawptr) {
	args := cast(^Credits_Job)data
	defer {
		delete(args.api_key)
		free(args)
	}
	bal := provider.openrouter_fetch_balance(args.api_key)
	defer delete(bal.err)
	defer delete(bal.label)
	label := provider.openrouter_balance_label(bal)
	delete(args.app.credits_label)
	args.app.credits_label = label
	args.app.credits_busy = false
	args.app.dirty = true
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
	return a.dirty || splash_active(a)
}


app_on_tick :: proc(user: rawptr) -> bool {
	a := cast(^App)user
	changed := false
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
	poll_changed := session.session_poll(&a.session)
	changed = poll_changed || changed
	if was_busy && !a.session.busy {
		app_refresh_credits(a)
		changed = true
		a.follow = true
		a.scroll = 0
	}
	// Redraw on new deltas, or on spinner/caret cadence while busy.
	// Avoid full transcript layout every poll tick with no UI change.
	if a.session.busy || a.session.has_streaming || a.session.has_thinking {
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
