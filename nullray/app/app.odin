// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
App shell: lifecycle, provider status, dirty flag, tick.
*/

package app

import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"
import "nullray:agent"
import "nullray:ask"
import "nullray:config"
import "nullray:constants"
import "nullray:mcp"
import "nullray:provider"
import "nullray:rag"
import "nullray:sandbox"
import "nullray:schedule"
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
	models_sess:    ^session.Session,
	session:        ^session.Session,
	tabs:           [dynamic]Tab,
	active_tab:     int,
	tab_x_prefix:   bool,
	tab_hits:       [dynamic]Tab_Hit,
	tab_plus_x:     int,
	tab_scroll:     int,
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
	help_btn_w:     int,
	improve_undo:   string,
	improving:      bool,
	improve_gen:    u64,
	improve_worker: ^thread.Thread,
	improve_pending_mu: sync.Mutex,
	improve_pending: bool,
	improve_pending_gen: u64,
	improve_pending_text: string,
	improve_pending_err:  string,
	models_busy:        bool,
	models_worker:      ^thread.Thread,
	models_pending_mu:  sync.Mutex,
	models_pending:     bool,
	models_text:        string,
	models_err:         string,
	pasting:        bool,
	credits_busy:   bool,
	credits_mu:     sync.Mutex,
	credits_worker: ^thread.Thread,
	splash_on:      bool,
	splash_start:   time.Tick,
	banner_sess:    int,
	banner_live:    int,
	banner_refresh: time.Tick,
	anim_tick:      time.Tick,
	agent_spinner:  ui.Spinner,
	view_open:      bool,
	view_path:      string,
	view_body:      string,
	view_scroll:    int,
	view_is_image:  bool,
	view_kitty_id:  u32,
	view_image_cols: int,
	view_image_rows: int,
	view_focus:     bool,
	view_recent:    [dynamic]string,
	view_idx:       int,
	view_err:       bool,
	view_strip_y:   int,
	view_strip_hits: [dynamic]View_Strip_Hit,
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
	llamacpp_live:      bool,
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
	pending_media:      [dynamic]provider.Media_Part,
	reveal_stream:      int,
	reveal_think:       int,
	reset_pending:      bool,
	elevate_active:     bool,
	elevate_id:         u64,
	elevate_prompt:     string,
	elevate_command:    string,
	elevate_buf:        string,
	ask_active:         bool,
	ask_id:             u64,
	ask_kind:           ask.Kind,
	ask_prompt:         string,
	ask_options:        [dynamic]string,
	ask_free:           bool,
	ask_sel:            int,
	ask_buf:            string,
	ask_editing:        bool,
	// Custom show_view form modal (Kind.View).
	view_form_active:   bool,
	view_form:          ask.View_Def,
	view_form_focus:    int,
	view_form_err:      string,
	view_form_scroll:   int,
	input_scroll_col:   int,
	view_auto:          bool,
	show_status:        bool,
	status_scroll:      int,
	status_body:        string,
	show_history:       bool,
	history_scroll:     int,
	layout_cache:       Layout_Cache,
	expand_hits:        [dynamic]Expand_Hit,
	expanded:           map[string]bool,
	expand_all:         bool,
}

app_init :: proc(a: ^App, loop: ^ui.Loop) {
	a^ = {}
	a.loop = loop
	tools.registry_init(&a.tools_reg)
	mcp.registry_init(&a.mcp_reg, &a.tools_reg)
	mcp.mcp_autoload(&a.mcp_reg)
	provider.registry_init(&a.registry)
	app_tabs_restore(a)
	if len(a.tabs) == 0 {
		s := app_session_alloc(a)
		append(&a.tabs, Tab{sess = s})
		a.active_tab = 0
	}
	app_tab_bind_active(a)
	rag.install_memory_hooks()
	rag.bind_providers(&a.registry, provider.registry_active(&a.registry))
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
	session.session_rebuild_system_prompt(a.session)
	strings.builder_init(&a.input)
	a.spinner = ui.spinner_init()
	a.agent_spinner = ui.spinner_init()
	// Wire set_tui so live loop theme refreshes when the agent recolors the UI.
	tools.register_tui_apply(app_tui_apply, a)
	// Export ask vault secrets into shell env when NULLRAY_VAULT_EXPORT=1.
	sandbox.register_vault_export(proc(dst: ^[dynamic]string, allocator: mem.Allocator) -> int {
		return ask.secret_export_env_pairs(dst, allocator)
	})
	// Load saved custom theme unless reset requested.
	if v, ok := os.lookup_env(constants.ENV_UI_RESET, context.temp_allocator); ok {
		switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
		case "1", "true", "on", "yes", "reset":
			_ = ui.theme_clear_custom()
		case:
			if t, tok := ui.theme_load_custom(); tok {
				ui.theme_set(t)
				if a.loop != nil {
					a.loop.theme = t
				}
			}
		}
	} else if t, tok := ui.theme_load_custom(); tok {
		ui.theme_set(t)
		if a.loop != nil {
			a.loop.theme = t
		}
	}
	a.dirty = true
	a.follow = true
	a.splash_on = splash_enabled_from_env()
	a.splash_start = time.tick_now()
	a.binds, a.keys_preset = config.load_binds()
	_ = config.write_default_keys_file()
	a.expanded = make(map[string]bool)
	a.hide_sensitive = hide_sensitive_from_env()
	app_refresh_banner(a)
	agent.apply_auto_mode()
	if agent.auto_from_env() {
		a.session.agent_mode = .Edit
		session.session_sync_mode_env(a.session)
		session.session_rebuild_system_prompt(a.session)
	}
	app_refresh_credits(a)

	cfg_dir := sandbox.resolve_config_dir(context.temp_allocator)
	if sid, recovered := session.crash_lock_recover(cfg_dir); recovered {
		if session.session_switch(a.session, sid) {
			_ = session.session_apply_saved_model(a.session, &a.registry)
			session.session_set_status(a.session, fmt.tprintf("recovered session %s after crash", sid))
		}
		delete(sid)
		session.crash_lock_clear(cfg_dir)
	}
	session.crash_lock_write(cfg_dir, a.session.name)
	provider.set_session(a.session.name)
	a.input_hist_idx = -1
	a.view_auto = view_auto_from_env()
	app_refresh_provider_status(a)
	if plan_in := agent.plan_in_from_env(); len(plan_in) > 0 {
		defer delete(plan_in)
		if err := session.session_seed_plan_file(a.session, plan_in); len(err) > 0 {
			session.session_set_status(a.session, err)
		} else {
			session.session_set_status(
				a.session,
				fmt.tprintf("plan loaded %s (use /approve)", a.session.last_plan_path),
			)
		}
	}
	app_maybe_begin_setup(a)
	ask.set_ui_enabled(true)
	schedule.schedule_init()
	app_schedule_bind(a)
	schedule.schedule_start()
}

app_destroy :: proc(a: ^App) {
	app_schedule_destroy()
	cfg_dir := sandbox.resolve_config_dir(context.temp_allocator)
	session.crash_lock_clear(cfg_dir)
	app_tabs_persist(a)
	for t in a.tabs {
		session.session_shutdown(t.sess)
		session.session_wakeup_forget(t.sess)
	}
	subagent.runtime_set(nil)
	subagent.runtime_destroy(&a.subagents)
	provider.registry_destroy(&a.registry)
	for t in a.tabs {
		if session.session_destroy(t.sess) {
			free(t.sess)
		}
	}
	delete(a.tabs)
	delete(a.tab_hits)
	a.session = nil
	mcp.registry_destroy(&a.mcp_reg)
	tools.registry_destroy(&a.tools_reg)
	strings.builder_destroy(&a.input)
	delete(a.improve_undo)
	// Give in-flight background workers a beat to finish before freeing the
	// fields they write. A worker still running keeps the memory (leak on
	// exit) instead of dangling into a freed App.
	improve_done := app_join_worker(&a.improve_worker, 800)
	if improve_done {
		delete(a.improve_pending_text)
		delete(a.improve_pending_err)
	}
	models_done := app_join_worker(&a.models_worker, 800)
	if models_done {
		delete(a.models_text)
		delete(a.models_err)
	}
	if app_join_worker(&a.credits_worker, 800) {
		delete(a.credits_label)
	}
	app_setup_clear(a)
	app_ask_clear(a)
	app_view_destroy(a)
	app_toasts_destroy(a)
	app_sel_destroy(a)
	app_history_destroy(a)
	app_media_clear(a)
	delete(a.input_draft)
	delete(a.status_body)
	app_expand_hits_clear(a)
	delete(a.expand_hits)
	for k in a.expanded {
		delete(k)
	}
	delete(a.expanded)
	app_layout_cache_clear(a)
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
	} else if !a.hide_sensitive {
		if cl := app_credits_label(a); len(cl) > 0 {
			status = fmt.tprintf("%s · %s", status, cl)
			delete(cl)
		}
	}
	session.session_set_status(a.session, status)
}

