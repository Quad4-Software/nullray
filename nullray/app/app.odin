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
import "nullray:provider"
import "nullray:sandbox"
import "nullray:session"
import "nullray:tools"
import "nullray:ui"

App :: struct {
	loop:           ^ui.Loop,
	registry:       provider.Registry,
	session:        session.Session,
	input:          strings.Builder,
	cursor:         int,
	dirty:          bool,
	spinner:        ui.Spinner,
	scroll:         int,
	follow:         bool,
	credits_label:  string,
	show_help:      bool,
	suggest_sel:    int,
	binds:          config.Binds,
	help_btn_x:     int,
	improve_undo:   string,
	improving:      bool,
	pasting:        bool,
	credits_busy:   bool,
	splash_on:      bool,
	splash_start:   time.Tick,
}

app_init :: proc(a: ^App, loop: ^ui.Loop) {
	a^ = {}
	a.loop = loop
	provider.registry_init(&a.registry)
	session.session_init(&a.session)
	_ = session.session_apply_saved_model(&a.session, &a.registry)
	strings.builder_init(&a.input)
	a.spinner = ui.spinner_init()
	a.dirty = true
	a.follow = true
	a.splash_on = true
	a.splash_start = time.tick_now()
	a.binds = config.load_binds()
	_ = config.write_default_keys_file()
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
			session.session_set_status(&a.session, fmt.tprintf("recovered session %s", sid))
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

app_is_dirty :: proc(user: rawptr) -> bool {
	a := cast(^App)user
	return a.dirty || a.session.busy || a.session.has_streaming || a.session.has_thinking || splash_active(a)
}


app_on_tick :: proc(user: rawptr) -> bool {
	a := cast(^App)user
	changed := false
	if splash_active(a) {
		changed = true
		app_mark_dirty(a)
	}
	was_busy := a.session.busy
	changed = session.session_poll(&a.session) || changed
	if was_busy && !a.session.busy {
		app_refresh_credits(a)
		changed = true
		a.follow = true
		a.scroll = 0
	}
	if a.session.busy || a.session.has_streaming || a.session.has_thinking {
		changed = true
		if a.follow {
			a.scroll = 0
		}
	}
	if changed {
		app_mark_dirty(a)
	}
	return changed
}

