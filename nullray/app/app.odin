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
import "nullray:subagent"
import "nullray:tools"
import "nullray:ui"

App :: struct {
	loop:           ^ui.Loop,
	registry:       provider.Registry,
	tools_reg:      tools.Registry,
	mcp_reg:        mcp.Registry,
	session:        session.Session,
	subagents:      subagent.Runtime,
	input:          strings.Builder,
	cursor:         int,
	dirty:          bool,
	spinner:        ui.Spinner,
	scroll:         int,
	follow:         bool,
	credits_label:  string,
	hide_sensitive: bool,
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
	view_open:      bool,
	view_path:      string,
	view_body:      string,
	view_scroll:    int,
	view_focus:     bool,
	view_recent:    [dynamic]string,
	view_idx:       int,
	show_setup:         bool,
	setup_forced:       bool,
	setup_step:         Setup_Step,
	setup_provider_sel: int,
	setup_scroll:       int,
	setup_field:        int,
	setup_base:         string,
	setup_key:          string,
	setup_model:        string,
	setup_filter:       string,
	setup_status:       string,
	setup_effort:       string,
	setup_thinking_on:  bool,
	setup_models:       []provider.Model_Info,
	setup_model_sel:    int,
	ollama_live:        bool,
	lmstudio_live:      bool,
	toasts:             [dynamic]Toast,
	sel_dragging:       bool,
	sel_has:            bool,
	sel_ax:             int,
	sel_ay:             int,
	sel_bx:             int,
	sel_by:             int,
	sel_rows:           [dynamic]string,
	sel_rows_top:       int,
	input_history:      [dynamic]string,
	input_hist_idx:     int,
	input_draft:        string,
	reveal_stream:      int,
	reveal_think:       int,
	reset_pending:      bool,
	elevate_active:     bool,
	elevate_id:         u64,
	elevate_prompt:     string,
	elevate_command:    string,
	elevate_buf:        string,
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
	subagent.runtime_init(&a.subagents, a.session.name, &a.tools_reg)
	subagent.runtime_set_session(&a.subagents, a.session.session_path, a.session.persist)
	subagent.runtime_set(&a.subagents)
	agent.register_subagent_runner()
	tools.register_subagent_tools(&a.tools_reg, subagent.runtime_enabled(&a.subagents))
	if p := provider.registry_active(&a.registry); p != nil {
		subagent.runtime_set_provider(&a.subagents, p)
		delete(a.subagents.main_model)
		a.subagents.main_model = strings.clone(p.default_model)
	}
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
	a.hide_sensitive = hide_sensitive_from_env()
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
	provider.set_session(a.session.name)
	a.input_hist_idx = -1
	app_refresh_provider_status(a)
	if plan_in := agent.plan_in_from_env(); len(plan_in) > 0 {
		defer delete(plan_in)
		if err := session.session_seed_plan_file(&a.session, plan_in); len(err) > 0 {
			session.session_set_status(&a.session, err)
		} else {
			session.session_set_status(
				&a.session,
				fmt.tprintf("plan loaded %s (use /approve)", a.session.last_plan_path),
			)
		}
	}
	app_maybe_begin_setup(a)
}

app_destroy :: proc(a: ^App) {
	cfg_dir := sandbox.resolve_config_dir(context.temp_allocator)
	session.crash_lock_clear(cfg_dir)
	subagent.runtime_set(nil)
	subagent.runtime_destroy(&a.subagents)
	provider.registry_destroy(&a.registry)
	session.session_destroy(&a.session)
	mcp.registry_destroy(&a.mcp_reg)
	tools.registry_destroy(&a.tools_reg)
	strings.builder_destroy(&a.input)
	delete(a.credits_label)
	delete(a.improve_undo)
	app_setup_clear(a)
	app_view_destroy(a)
	app_toasts_destroy(a)
	app_sel_destroy(a)
	app_history_destroy(a)
	delete(a.input_draft)
	app_elevate_clear(a)
}

app_refresh_provider_status :: proc(a: ^App) {
	p := provider.registry_active(&a.registry)
	if p == nil {
		return
	}
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
	} else if !a.hide_sensitive && len(a.credits_label) > 0 {
		status = fmt.tprintf("%s · %s", status, a.credits_label)
	}
	session.session_set_status(&a.session, status)
}

app_refresh_credits :: proc(a: ^App) {
	if a.hide_sensitive {
		delete(a.credits_label)
		a.credits_label = ""
		return
	}
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
	if args.app.hide_sensitive {
		delete(args.app.credits_label)
		args.app.credits_label = ""
		args.app.credits_busy = false
		args.app.dirty = true
		return
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

hide_sensitive_from_env :: proc() -> bool {
	if v, ok := os.lookup_env(constants.ENV_HIDE_SENSITIVE, context.temp_allocator); ok {
		switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
		case "1", "true", "on", "yes", "hide":
			return true
		case "0", "false", "off", "no", "show":
			return false
		}
	}
	return false
}

app_set_hide_sensitive :: proc(a: ^App, hide: bool) {
	a.hide_sensitive = hide
	if hide {
		os.set_env(constants.ENV_HIDE_SENSITIVE, "1")
		delete(a.credits_label)
		a.credits_label = ""
	} else {
		os.unset_env(constants.ENV_HIDE_SENSITIVE)
		app_refresh_credits(a)
	}
	app_refresh_provider_status(a)
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
	return a.dirty || splash_active(a) || a.show_setup || a.elevate_active || len(a.toasts) > 0 || a.sel_dragging
}


app_on_tick :: proc(user: rawptr) -> bool {
	a := cast(^App)user
	changed := false
	if app_elevate_poll(a) {
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
	if session.session_tick_status_hold(&a.session) {
		changed = true
	}
	poll_changed := session.session_poll(&a.session)
	changed = poll_changed || changed
	if app_reveal_tick(a) {
		changed = true
	}
	if was_busy && !a.session.busy {
		app_reveal_reset(a)
		app_refresh_credits(a)
		changed = true
		a.follow = true
		a.scroll = 0
		paths := collect_turn_write_paths(a.session.messages[:], context.allocator)
		if len(paths) > 0 {
			app_view_set_recent(a, paths)
			last := paths[len(paths) - 1]
			_ = app_view_open(a, last)
			destroy_write_paths(paths)
			changed = true
		} else {
			destroy_write_paths(paths)
		}
	}
	// Redraw on new deltas, or on spinner/caret/reveal cadence while busy.
	// Avoid full transcript layout every poll tick with no UI change.
	if a.session.busy || a.session.has_streaming || a.session.has_thinking || len(a.session.pending_status) > 0 {
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
