// SPDX-License-Identifier: 0BSD
/*
TUI-only setup overlay. Prefer /setup. Auto-opens when setup_needed.
Never used from --print or --self-test.
*/

package app

import "core:fmt"
import "core:os"
import "core:strings"
import "core:unicode/utf8"
import "nullray:config"
import "nullray:constants"
import "nullray:provider"
import "nullray:session"
import "nullray:ui"

Setup_Step :: enum {
	Provider,
	Connection,
	Model,
	Reasoning,
	Confirm,
}

SETUP_EFFORTS := []string{"none", "minimal", "low", "medium", "high", "xhigh", "max"}

@(private)
setup_env_configured :: proc() -> bool {
	// Env or flags (--provider writes ENV_PROVIDER before we run) already
	// name a provider, key, model, or host. Trust it and skip the wizard.
	keys := []string{
		constants.ENV_PROVIDER,
		constants.ENV_API_KEY,
		constants.ENV_MODEL,
		constants.ENV_BASE_URL,
		constants.ENV_OLLAMA_HOST,
		constants.ENV_LMSTUDIO_HOST,
		constants.ENV_LLAMACPP_HOST,
		constants.ENV_OPENAI_BASE,
	}
	for key in keys {
		if v, ok := os.lookup_env(key, context.temp_allocator); ok && len(strings.trim_space(v)) > 0 {
			return true
		}
	}
	return false
}

setup_needed :: proc(a: ^App) -> bool {
	if config.setup_done_from_env() || setup_env_configured() {
		return false
	}
	p := provider.registry_active(&a.registry)
	if p != nil {
		if provider.provider_is_local(p.id) {
			if provider.local_probe_enabled_from_env() &&
			   provider.probe_local_provider(p.id, 2) {
				return false
			}
		} else if len(p.api_key) > 0 {
			return false
		}
	}
	if provider.local_probe_enabled_from_env() &&
	   (provider.probe_local_provider("ollama", 2) ||
	    provider.probe_local_provider("lmstudio", 2) ||
	    provider.probe_local_provider("llamacpp", 2)) {
		return false
	}
	return true
}

app_maybe_begin_setup :: proc(a: ^App) {
	if a.show_setup {
		return
	}
	if !setup_needed(a) {
		return
	}
	app_setup_open(a, true)
}

app_setup_open :: proc(a: ^App, forced: bool) {
	app_setup_clear(a)
	a.show_setup = true
	a.setup_forced = forced
	a.setup_step = .Provider
	a.ollama_live = false
	a.lmstudio_live = false
	a.llamacpp_live = false
	if provider.local_probe_enabled_from_env() {
		a.ollama_live = provider.probe_local_provider("ollama", 2)
		a.lmstudio_live = provider.probe_local_provider("lmstudio", 2)
		a.llamacpp_live = provider.probe_local_provider("llamacpp", 2)
	}
	a.setup_provider_sel = 0
	if a.ollama_live {
		a.setup_provider_sel = setup_provider_index(a, "ollama")
	} else if a.lmstudio_live {
		a.setup_provider_sel = setup_provider_index(a, "lmstudio")
	} else if a.llamacpp_live {
		a.setup_provider_sel = setup_provider_index(a, "llamacpp")
	} else if p := provider.registry_active(&a.registry); p != nil {
		a.setup_provider_sel = setup_provider_index(a, p.id)
	}
	setup_apply_provider_defaults(a)
	app_mark_dirty(a)
}

app_setup_clear :: proc(a: ^App) {
	delete(a.setup_base)
	delete(a.setup_key)
	delete(a.setup_model)
	delete(a.setup_filter)
	delete(a.setup_status)
	delete(a.setup_effort)
	provider.destroy_models(a.setup_models)
	a.setup_base = ""
	a.setup_key = ""
	a.setup_model = ""
	a.setup_filter = ""
	a.setup_status = ""
	a.setup_effort = ""
	a.setup_models = nil
	a.setup_model_sel = 0
	a.setup_scroll = 0
	a.setup_field = 0
	a.setup_thinking_on = true
}

app_setup_close :: proc(a: ^App) {
	a.show_setup = false
	a.setup_forced = false
	app_setup_clear(a)
	app_mark_dirty(a)
}

@(private)
setup_provider_index :: proc(a: ^App, id: string) -> int {
	for p, i in a.registry.providers {
		if p.id == id {
			return i
		}
	}
	return 0
}

@(private)
setup_selected_provider :: proc(a: ^App) -> ^provider.Provider {
	n := len(a.registry.providers)
	if n == 0 {
		return nil
	}
	if a.setup_provider_sel < 0 {
		a.setup_provider_sel = 0
	}
	if a.setup_provider_sel >= n {
		a.setup_provider_sel = n - 1
	}
	return &a.registry.providers[a.setup_provider_sel]
}

@(private)
setup_provider_key_env :: proc(id: string) -> string {
	switch id {
	case "openrouter":
		return constants.ENV_OPENROUTER_KEY
	case "opencode", "opencode-go":
		return constants.ENV_OPENCODE_KEY
	case "openai", "openai-compat":
		return constants.ENV_OPENAI_KEY
	case "anthropic":
		return constants.ENV_ANTHROPIC_KEY
	case "gemini":
		return constants.ENV_GEMINI_KEY
	case "groq":
		return constants.ENV_GROQ_KEY
	case "deepseek":
		return constants.ENV_DEEPSEEK_KEY
	case "mistral":
		return constants.ENV_MISTRAL_KEY
	case "together":
		return constants.ENV_TOGETHER_KEY
	case "fireworks":
		return constants.ENV_FIREWORKS_KEY
	case "xai":
		return constants.ENV_XAI_KEY
	case "azure":
		return constants.ENV_AZURE_KEY
	case "cerebras":
		return constants.ENV_CEREBRAS_KEY
	case "cohere":
		return constants.ENV_COHERE_KEY
	case "nvidia":
		return constants.ENV_NVIDIA_KEY
	case "dashscope":
		return constants.ENV_DASHSCOPE_KEY
	case "lmstudio":
		return constants.ENV_LMSTUDIO_KEY
	case "llamacpp":
		return constants.ENV_LLAMACPP_KEY
	}
	return ""
}

@(private)
setup_provider_host_env :: proc(id: string) -> string {
	switch id {
	case "ollama":
		return constants.ENV_OLLAMA_HOST
	case "lmstudio":
		return constants.ENV_LMSTUDIO_HOST
	case "llamacpp":
		return constants.ENV_LLAMACPP_HOST
	case "openai", "openai-compat":
		return constants.ENV_OPENAI_BASE
	case "azure":
		return constants.ENV_AZURE_BASE
	}
	return constants.ENV_BASE_URL
}

@(private)
setup_provider_needs_key :: proc(id: string) -> bool {
	// lmstudio still shows the token field (default lm-studio).
	return id == "lmstudio" || !provider.provider_is_local(id)
}

@(private)
setup_env_or :: proc(keys: []string, fallback: string) -> string {
	for k in keys {
		if len(k) == 0 {
			continue
		}
		if v, ok := os.lookup_env(k, context.temp_allocator); ok && len(strings.trim_space(v)) > 0 {
			return strings.clone(strings.trim_space(v))
		}
	}
	return strings.clone(fallback)
}

@(private)
setup_apply_provider_defaults :: proc(a: ^App) {
	p := setup_selected_provider(a)
	if p == nil {
		return
	}
	delete(a.setup_base)
	delete(a.setup_key)
	delete(a.setup_model)
	delete(a.setup_effort)
	host_env := setup_provider_host_env(p.id)
	key_env := setup_provider_key_env(p.id)
	a.setup_base = setup_env_or({host_env, constants.ENV_BASE_URL}, p.base_url)
	a.setup_key = setup_env_or({key_env, constants.ENV_API_KEY}, p.api_key)
	a.setup_model = setup_env_or({constants.ENV_MODEL}, p.default_model)
	if provider.provider_is_local(p.id) || p.id == "anthropic" {
		a.setup_effort = strings.clone("none")
		a.setup_thinking_on = false
	} else {
		a.setup_effort = setup_env_or({constants.ENV_REASONING}, constants.DEFAULT_REASONING)
		a.setup_thinking_on = a.setup_effort != "none"
	}
	a.setup_field = 0
	provider.destroy_models(a.setup_models)
	a.setup_models = nil
	a.setup_model_sel = 0
	delete(a.setup_status)
	a.setup_status = ""
}

@(private)
setup_set_status :: proc(a: ^App, msg: string) {
	delete(a.setup_status)
	a.setup_status = strings.clone(msg)
}

@(private)
setup_draft_provider :: proc(a: ^App) -> (provider.Provider, bool) {
	src := setup_selected_provider(a)
	if src == nil {
		return {}, false
	}
	p := provider.Provider{
		id = strings.clone(src.id),
		name = strings.clone(src.name),
		base_url = strings.clone(a.setup_base),
		api_key = strings.clone(a.setup_key),
		default_model = strings.clone(a.setup_model),
		chat = src.chat,
		stream = src.stream,
		list_models = src.list_models,
	}
	return p, true
}

@(private)
setup_load_models :: proc(a: ^App) {
	provider.destroy_models(a.setup_models)
	a.setup_models = nil
	a.setup_model_sel = 0
	setup_set_status(a, "loading models…")
	app_mark_dirty(a)

	p, ok := setup_draft_provider(a)
	if !ok {
		setup_set_status(a, "no provider")
		return
	}
	defer provider.provider_destroy(&p)

	models: []provider.Model_Info
	err: string
	switch p.id {
	case "ollama":
		models, err = provider.ollama_list_models_timeout(&p, 8)
	case "lmstudio":
		models, err = provider.lmstudio_list_models_timeout(&p, 8)
	case "llamacpp":
		models, err = provider.llamacpp_list_models_timeout(&p, 8)
	case:
		models, err = provider.openai_list_models_timeout(&p, 15)
	}
	if len(err) > 0 {
		setup_set_status(a, fmt.tprintf("list failed: %s (type a model id)", err))
		delete(err)
		a.setup_models = nil
		return
	}
	a.setup_models = models
	if len(models) > 0 {
		delete(a.setup_model)
		a.setup_model = strings.clone(models[0].id)
		setup_apply_model_reasoning(a, &models[0])
		setup_set_status(a, fmt.tprintf("%d models", len(models)))
	} else {
		setup_set_status(a, "no models returned (type a model id)")
	}
}

@(private)
setup_apply_model_reasoning :: proc(a: ^App, m: ^provider.Model_Info) {
	if m == nil || !m.has_reasoning_meta {
		return
	}
	a.setup_thinking_on = m.reasoning_default_on || m.reasoning_mandatory
	if m.reasoning_mandatory {
		a.setup_thinking_on = true
	}
	delete(a.setup_effort)
	if a.setup_thinking_on {
		if len(m.reasoning_default) > 0 && m.reasoning_default != "none" {
			a.setup_effort = strings.clone(m.reasoning_default)
		} else {
			a.setup_effort = strings.clone("low")
		}
	} else {
		a.setup_effort = strings.clone("none")
	}
}

@(private)
setup_filtered_model_count :: proc(a: ^App) -> int {
	n := 0
	filt := strings.to_lower(a.setup_filter, context.temp_allocator)
	for m in a.setup_models {
		if len(filt) == 0 || strings.contains(strings.to_lower(m.id, context.temp_allocator), filt) {
			n += 1
		}
	}
	return n
}

@(private)
setup_filtered_model_at :: proc(a: ^App, want: int) -> (^provider.Model_Info, bool) {
	n := 0
	filt := strings.to_lower(a.setup_filter, context.temp_allocator)
	for &m in a.setup_models {
		if len(filt) == 0 || strings.contains(strings.to_lower(m.id, context.temp_allocator), filt) {
			if n == want {
				return &m, true
			}
			n += 1
		}
	}
	return nil, false
}

@(private)
setup_reason_efforts :: proc(a: ^App) -> []string {
	if m, ok := setup_filtered_model_at(a, a.setup_model_sel); ok && m.has_reasoning_meta && len(m.reasoning_efforts) > 0 {
		return m.reasoning_efforts
	}
	return SETUP_EFFORTS
}

@(private)
setup_skip_reasoning_step :: proc(a: ^App) -> bool {
	p := setup_selected_provider(a)
	if p == nil {
		return true
	}
	return p.id == "anthropic" || provider.provider_is_local(p.id)
}

@(private)
setup_reason_value :: proc(a: ^App) -> string {
	p := setup_selected_provider(a)
	if p == nil {
		return "low"
	}
	if p.id == "anthropic" || provider.provider_is_local(p.id) {
		return "none"
	}
	switch p.id {
	case "dashscope", "cohere":
		if a.setup_thinking_on {
			return "low"
		}
		return "none"
	case "deepseek":
		if !a.setup_thinking_on {
			return "none"
		}
		if len(a.setup_effort) == 0 || a.setup_effort == "none" {
			return "low"
		}
		return a.setup_effort
	}
	if !a.setup_thinking_on {
		return "none"
	}
	if len(a.setup_effort) == 0 {
		return "low"
	}
	return a.setup_effort
}

@(private)
setup_can_advance :: proc(a: ^App) -> bool {
	p := setup_selected_provider(a)
	if p == nil {
		return false
	}
	switch a.setup_step {
	case .Provider:
		return true
	case .Connection:
		if p.id == "openai-compat" || p.id == "azure" {
			if len(strings.trim_space(a.setup_base)) == 0 {
				setup_set_status(a, "base URL required")
				return false
			}
		}
		if setup_provider_needs_key(p.id) && p.id != "lmstudio" {
			if len(strings.trim_space(a.setup_key)) == 0 {
				setup_set_status(a, "API key required")
				return false
			}
		}
		return true
	case .Model:
		if len(strings.trim_space(a.setup_model)) == 0 {
			setup_set_status(a, "model required")
			return false
		}
		return true
	case .Reasoning, .Confirm:
		return true
	}
	return false
}

@(private)
setup_next_step :: proc(a: ^App) {
	if !setup_can_advance(a) {
		app_mark_dirty(a)
		return
	}
	switch a.setup_step {
	case .Provider:
		setup_apply_provider_defaults(a)
		a.setup_step = .Connection
	case .Connection:
		a.setup_step = .Model
		setup_load_models(a)
	case .Model:
		if setup_skip_reasoning_step(a) {
			a.setup_step = .Confirm
		} else {
			a.setup_step = .Reasoning
		}
	case .Reasoning:
		a.setup_step = .Confirm
	case .Confirm:
		setup_save(a)
	}
	app_mark_dirty(a)
}

@(private)
setup_prev_step :: proc(a: ^App) {
	switch a.setup_step {
	case .Provider:
		if a.setup_forced {
			setup_set_status(a, "finish setup or pick a live local provider")
		} else {
			app_setup_close(a)
		}
	case .Connection:
		a.setup_step = .Provider
	case .Model:
		a.setup_step = .Connection
	case .Reasoning:
		a.setup_step = .Model
	case .Confirm:
		if setup_skip_reasoning_step(a) {
			a.setup_step = .Model
		} else {
			a.setup_step = .Reasoning
		}
	}
	app_mark_dirty(a)
}

@(private)
setup_mask_key :: proc(key: string) -> string {
	k := strings.trim_space(key)
	if len(k) == 0 {
		return "(none)"
	}
	if len(k) <= 8 {
		return "********"
	}
	return fmt.tprintf("%s…%s", k[:4], k[len(k) - 4:])
}

@(private)
setup_save :: proc(a: ^App) {
	p := setup_selected_provider(a)
	if p == nil {
		return
	}
	effort := setup_reason_value(a)
	if _, ok := session.normalize_reasoning_effort(effort); !ok {
		effort = constants.DEFAULT_REASONING
	}

	kvs := make([dynamic]config.Env_KV, context.temp_allocator)
	append(&kvs, config.Env_KV{key = constants.ENV_PROVIDER, val = p.id})
	append(&kvs, config.Env_KV{key = constants.ENV_MODEL, val = strings.trim_space(a.setup_model)})
	append(&kvs, config.Env_KV{key = constants.ENV_REASONING, val = effort})
	append(&kvs, config.Env_KV{key = constants.ENV_SETUP_DONE, val = "1"})

	host_env := setup_provider_host_env(p.id)
	if len(strings.trim_space(a.setup_base)) > 0 && len(host_env) > 0 {
		append(&kvs, config.Env_KV{key = host_env, val = strings.trim_space(a.setup_base)})
	}
	key_env := setup_provider_key_env(p.id)
	if setup_provider_needs_key(p.id) && len(strings.trim_space(a.setup_key)) > 0 && len(key_env) > 0 {
		append(&kvs, config.Env_KV{key = key_env, val = strings.trim_space(a.setup_key)})
	}

	if err := config.merge_env_keys(kvs[:]); len(err) > 0 {
		setup_set_status(a, err)
		delete(err)
		app_mark_dirty(a)
		return
	}

	provider.registry_destroy(&a.registry)
	provider.registry_init(&a.registry)
	_ = provider.registry_set_active(&a.registry, p.id)
	if ap := provider.registry_active(&a.registry); ap != nil {
		delete(ap.default_model)
		ap.default_model = strings.clone(strings.trim_space(a.setup_model))
		session.session_remember_model(&a.session, ap.id, ap.default_model)
	}
	delete(a.session.reasoning_effort)
	a.session.reasoning_effort = strings.clone(effort)
	os.set_env(constants.ENV_REASONING, effort)

	app_setup_close(a)
	app_refresh_provider_status(a)
	app_refresh_credits(a)
	session.session_set_status(&a.session, "setup saved to ~/.config/nullray/env")
}

app_draw_setup :: proc(buf: ^ui.Buffer, a: ^App) {
	t := ui.theme()
	ui.buffer_clear(buf, t.bg, t.fg)
	title := "nullray setup"
	ui.draw_status_bar(buf, 0, title, "Tab/Enter next · Esc back", t.title, t.status_bg)
	ui.buffer_hline(buf, 0, 1, buf.width, '─', t.border, t.bg)

	y := 2
	step_name := "provider"
	switch a.setup_step {
	case .Provider:
		step_name = "1/5 provider (local / cloud)"
	case .Connection:
		step_name = "2/5 connection"
	case .Model:
		step_name = "3/5 model"
	case .Reasoning:
		step_name = "4/5 reasoning"
	case .Confirm:
		step_name = "5/5 confirm"
	}
	ui.buffer_text_clip(buf, 1, y, buf.width - 1, step_name, t.accent, t.bg, {.Bold})
	y += 2

	switch a.setup_step {
	case .Provider:
		setup_draw_provider_list(buf, a, y)
	case .Connection:
		setup_draw_connection(buf, a, y)
	case .Model:
		setup_draw_model(buf, a, y)
	case .Reasoning:
		setup_draw_reasoning(buf, a, y)
	case .Confirm:
		setup_draw_confirm(buf, a, y)
	}

	foot := a.setup_status
	if len(foot) == 0 {
		if a.setup_step == .Provider {
			foot = "local hosts first, then cloud APIs"
		} else {
			foot = "config first, then defaults"
		}
	}
	ui.draw_status_bar(buf, buf.height - 1, foot, "/setup later", t.status_fg, t.status_bg)
}

Setup_Prov_Row_Kind :: enum {
	Header,
	Item,
}

Setup_Prov_Row :: struct {
	kind:         Setup_Prov_Row_Kind,
	label:        string,
	provider_idx: int,
}

@(private)
setup_provider_live_badge :: proc(a: ^App, id: string) -> string {
	switch id {
	case "ollama":
		if a.ollama_live {
			return " live"
		}
	case "lmstudio":
		if a.lmstudio_live {
			return " live"
		}
	case "llamacpp":
		if a.llamacpp_live {
			return " live"
		}
	}
	return ""
}

@(private)
setup_provider_rows :: proc(a: ^App, allocator := context.temp_allocator) -> []Setup_Prov_Row {
	rows := make([dynamic]Setup_Prov_Row, allocator)
	local_n := 0
	cloud_n := 0
	for p in a.registry.providers {
		if provider.provider_is_local(p.id) {
			local_n += 1
		} else {
			cloud_n += 1
		}
	}
	if local_n > 0 {
		append(&rows, Setup_Prov_Row{kind = .Header, label = "Local", provider_idx = -1})
		for p, i in a.registry.providers {
			if provider.provider_is_local(p.id) {
				append(&rows, Setup_Prov_Row{kind = .Item, label = "", provider_idx = i})
			}
		}
	}
	if cloud_n > 0 {
		append(&rows, Setup_Prov_Row{kind = .Header, label = "Cloud", provider_idx = -1})
		for p, i in a.registry.providers {
			if !provider.provider_is_local(p.id) {
				append(&rows, Setup_Prov_Row{kind = .Item, label = "", provider_idx = i})
			}
		}
	}
	return rows[:]
}

@(private)
setup_provider_sel_row :: proc(rows: []Setup_Prov_Row, provider_idx: int) -> int {
	for row, i in rows {
		if row.kind == .Item && row.provider_idx == provider_idx {
			return i
		}
	}
	return 0
}

@(private)
setup_provider_move :: proc(a: ^App, delta: int) {
	rows := setup_provider_rows(a)
	if len(rows) == 0 {
		return
	}
	cur := setup_provider_sel_row(rows, a.setup_provider_sel)
	next := cur
	step := 1 if delta > 0 else -1
	remain := abs(delta)
	for remain > 0 {
		next += step
		if next < 0 || next >= len(rows) {
			break
		}
		if rows[next].kind == .Item {
			remain -= 1
			a.setup_provider_sel = rows[next].provider_idx
		}
	}
}

@(private)
setup_draw_provider_list :: proc(buf: ^ui.Buffer, a: ^App, start_y: int) {
	t := ui.theme()
	rows := setup_provider_rows(a)
	view_h := max(1, buf.height - start_y - 2)
	sel_row := setup_provider_sel_row(rows, a.setup_provider_sel)
	if sel_row < a.setup_scroll {
		a.setup_scroll = sel_row
	}
	if sel_row >= a.setup_scroll + view_h {
		a.setup_scroll = sel_row - view_h + 1
	}
	y := start_y
	for i in a.setup_scroll ..< min(len(rows), a.setup_scroll + view_h) {
		row := rows[i]
		ui.buffer_fill_rect(buf, 0, y, buf.width, 1, ' ', t.fg, t.bg)
		switch row.kind {
		case .Header:
			ui.buffer_text_clip(buf, 1, y, buf.width - 1, row.label, t.muted, t.bg, {.Dim, .Bold})
		case .Item:
			p := a.registry.providers[row.provider_idx]
			mark := " "
			fg := t.fg
			if row.provider_idx == a.setup_provider_sel {
				mark = ">"
				fg = t.accent
			}
			badge := setup_provider_live_badge(a, p.id)
			line := fmt.tprintf("%s %s (%s)%s", mark, p.name, p.id, badge)
			ui.buffer_text_clip(buf, 1, y, buf.width - 1, line, fg, t.bg)
		}
		y += 1
	}
}

@(private)
setup_draw_connection :: proc(buf: ^ui.Buffer, a: ^App, start_y: int) {
	t := ui.theme()
	p := setup_selected_provider(a)
	name := "?"
	if p != nil {
		name = p.id
	}
	ui.buffer_text_clip(buf, 1, start_y, buf.width - 1, fmt.tprintf("provider: %s", name), t.muted, t.bg)
	base_mark := " "
	key_mark := " "
	if a.setup_field == 0 {
		base_mark = ">"
	} else {
		key_mark = ">"
	}
	ui.buffer_text_clip(buf, 1, start_y + 2, buf.width - 1, fmt.tprintf("%s base: %s", base_mark, a.setup_base), t.fg, t.bg)
	if p != nil && setup_provider_needs_key(p.id) {
		shown := a.setup_key
		if p.id != "lmstudio" && len(shown) > 0 {
			shown = setup_mask_key(shown)
			if a.setup_field == 1 {
				shown = a.setup_key
			}
		}
		ui.buffer_text_clip(buf, 1, start_y + 3, buf.width - 1, fmt.tprintf("%s key:  %s", key_mark, shown), t.fg, t.bg)
		ui.buffer_text_clip(buf, 1, start_y + 5, buf.width - 1, "Up/Down field · type to edit · Enter next", t.muted, t.bg, {.Dim})
	} else {
		ui.buffer_text_clip(buf, 1, start_y + 3, buf.width - 1, "no API key required", t.muted, t.bg, {.Dim})
	}
	ui.buffer_text_clip(buf, 1, start_y + 7, buf.width - 1, setup_oauth_note(name), t.muted, t.bg, {.Dim})
}

@(private)
setup_draw_model :: proc(buf: ^ui.Buffer, a: ^App, start_y: int) {
	t := ui.theme()
	ui.buffer_text_clip(buf, 1, start_y, buf.width - 1, fmt.tprintf("model: %s", a.setup_model), t.fg, t.bg)
	ui.buffer_text_clip(buf, 1, start_y + 1, buf.width - 1, fmt.tprintf("filter: %s", a.setup_filter), t.muted, t.bg)
	y := start_y + 3
	view_h := max(1, buf.height - y - 2)
	count := setup_filtered_model_count(a)
	if a.setup_model_sel < a.setup_scroll {
		a.setup_scroll = a.setup_model_sel
	}
	if a.setup_model_sel >= a.setup_scroll + view_h {
		a.setup_scroll = a.setup_model_sel - view_h + 1
	}
	shown := 0
	filt := strings.to_lower(a.setup_filter, context.temp_allocator)
	idx := 0
	for m in a.setup_models {
		if len(filt) > 0 && !strings.contains(strings.to_lower(m.id, context.temp_allocator), filt) {
			continue
		}
		if idx < a.setup_scroll {
			idx += 1
			continue
		}
		if shown >= view_h {
			break
		}
		mark := " "
		fg := t.fg
		if idx == a.setup_model_sel {
			mark = ">"
			fg = t.accent
		}
		ui.buffer_text_clip(buf, 1, y, buf.width - 1, fmt.tprintf("%s %s", mark, m.id), fg, t.bg)
		y += 1
		shown += 1
		idx += 1
	}
	if count == 0 {
		ui.buffer_text_clip(buf, 1, y, buf.width - 1, "type a model id then Enter", t.muted, t.bg, {.Dim})
	}
}

@(private)
setup_draw_reasoning :: proc(buf: ^ui.Buffer, a: ^App, start_y: int) {
	t := ui.theme()
	p := setup_selected_provider(a)
	pid := ""
	if p != nil {
		pid = p.id
	}
	ui.buffer_text_clip(buf, 1, start_y, buf.width - 1, fmt.tprintf("thinking: %s", a.setup_thinking_on ? "on" : "off"), t.fg, t.bg)
	ui.buffer_text_clip(buf, 1, start_y + 1, buf.width - 1, fmt.tprintf("effort: %s", a.setup_effort), t.fg, t.bg)
	ui.buffer_text_clip(buf, 1, start_y + 3, buf.width - 1, "Space toggles thinking · Left/Right effort", t.muted, t.bg, {.Dim})
	if pid == "dashscope" || pid == "cohere" {
		ui.buffer_text_clip(buf, 1, start_y + 4, buf.width - 1, "this provider maps to on/off on the wire", t.muted, t.bg, {.Dim})
	}
	effs := setup_reason_efforts(a)
	line := "levels:"
	for e in effs {
		line = fmt.tprintf("%s %s", line, e)
	}
	ui.buffer_text_clip(buf, 1, start_y + 6, buf.width - 1, line, t.muted, t.bg)
}

@(private)
setup_draw_confirm :: proc(buf: ^ui.Buffer, a: ^App, start_y: int) {
	t := ui.theme()
	p := setup_selected_provider(a)
	pid := "?"
	if p != nil {
		pid = p.id
	}
	ui.buffer_text_clip(buf, 1, start_y, buf.width - 1, fmt.tprintf("provider: %s", pid), t.fg, t.bg)
	ui.buffer_text_clip(buf, 1, start_y + 1, buf.width - 1, fmt.tprintf("base:     %s", a.setup_base), t.fg, t.bg)
	ui.buffer_text_clip(buf, 1, start_y + 2, buf.width - 1, fmt.tprintf("key:      %s", setup_mask_key(a.setup_key)), t.fg, t.bg)
	ui.buffer_text_clip(buf, 1, start_y + 3, buf.width - 1, fmt.tprintf("model:    %s", a.setup_model), t.fg, t.bg)
	ui.buffer_text_clip(buf, 1, start_y + 4, buf.width - 1, fmt.tprintf("reason:   %s", setup_reason_value(a)), t.fg, t.bg)
	ui.buffer_text_clip(buf, 1, start_y + 6, buf.width - 1, "Enter writes ~/.config/nullray/env", t.accent, t.bg)
}

app_setup_on_event :: proc(a: ^App, ev: ui.Event) -> bool {
	if ev.kind == .Ctrl_Q || ev.kind == .Ctrl_C {
		return true
	}
	if ev.kind == .Esc {
		setup_prev_step(a)
		return false
	}
	if ev.kind == .Tab || ev.kind == .Enter {
		if a.setup_step == .Model {
			if m, ok := setup_filtered_model_at(a, a.setup_model_sel); ok {
				delete(a.setup_model)
				a.setup_model = strings.clone(m.id)
				setup_apply_model_reasoning(a, m)
			}
		}
		setup_next_step(a)
		return false
	}

	#partial switch a.setup_step {
	case .Provider:
		#partial switch ev.kind {
		case .Up, .Mouse_Wheel_Up:
			setup_provider_move(a, -1)
			app_mark_dirty(a)
		case .Down, .Mouse_Wheel_Down:
			setup_provider_move(a, 1)
			app_mark_dirty(a)
		}
	case .Connection:
		#partial switch ev.kind {
		case .Up:
			a.setup_field = 0
			app_mark_dirty(a)
		case .Down:
			if p := setup_selected_provider(a); p != nil && setup_provider_needs_key(p.id) {
				a.setup_field = 1
			}
			app_mark_dirty(a)
		case .Backspace:
			setup_edit_backspace(a)
		case .Rune:
			if ev.ch >= 0x20 {
				setup_edit_insert(a, ev.ch)
			}
		}
	case .Model:
		#partial switch ev.kind {
		case .Up, .Mouse_Wheel_Up:
			a.setup_model_sel = max(0, a.setup_model_sel - 1)
			if m, ok := setup_filtered_model_at(a, a.setup_model_sel); ok {
				delete(a.setup_model)
				a.setup_model = strings.clone(m.id)
			}
			app_mark_dirty(a)
		case .Down, .Mouse_Wheel_Down:
			max_i := max(0, setup_filtered_model_count(a) - 1)
			a.setup_model_sel = min(max_i, a.setup_model_sel + 1)
			if m, ok := setup_filtered_model_at(a, a.setup_model_sel); ok {
				delete(a.setup_model)
				a.setup_model = strings.clone(m.id)
			}
			app_mark_dirty(a)
		case .Backspace:
			setup_filter_backspace(a)
			if len(a.setup_models) == 0 {
				setup_model_backspace(a)
			}
			a.setup_model_sel = 0
			app_mark_dirty(a)
		case .Rune:
			if ev.ch >= 0x20 {
				setup_filter_insert(a, ev.ch)
				a.setup_model_sel = 0
				app_mark_dirty(a)
			}
		}
	case .Reasoning:
		#partial switch ev.kind {
		case .Rune:
			if ev.ch == ' ' {
				p := setup_selected_provider(a)
				if p != nil {
					if m, ok := setup_filtered_model_at(a, a.setup_model_sel); ok && m.reasoning_mandatory {
						a.setup_thinking_on = true
					} else {
						a.setup_thinking_on = !a.setup_thinking_on
					}
				}
				if !a.setup_thinking_on {
					delete(a.setup_effort)
					a.setup_effort = strings.clone("none")
				} else if a.setup_effort == "none" || len(a.setup_effort) == 0 {
					delete(a.setup_effort)
					a.setup_effort = strings.clone("low")
				}
				app_mark_dirty(a)
			}
		case .Left:
			setup_effort_nudge(a, -1)
		case .Right:
			setup_effort_nudge(a, 1)
		}
	case .Confirm:
	}
	return false
}

@(private)
setup_edit_target :: proc(a: ^App) -> ^string {
	if a.setup_field == 1 {
		return &a.setup_key
	}
	return &a.setup_base
}

@(private)
setup_edit_backspace :: proc(a: ^App) {
	target := setup_edit_target(a)
	if len(target^) == 0 {
		return
	}
	_, sz := utf8.decode_last_rune_in_string(target^)
	if sz <= 0 {
		sz = 1
	}
	n := strings.clone(target^[:len(target^) - sz])
	delete(target^)
	target^ = n
	app_mark_dirty(a)
}

@(private)
setup_edit_insert :: proc(a: ^App, ch: rune) {
	target := setup_edit_target(a)
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	strings.write_string(&b, target^)
	strings.write_rune(&b, ch)
	nstr := strings.clone(strings.to_string(b))
	delete(target^)
	target^ = nstr
	app_mark_dirty(a)
}

@(private)
setup_filter_backspace :: proc(a: ^App) {
	if len(a.setup_filter) == 0 {
		return
	}
	_, sz := utf8.decode_last_rune_in_string(a.setup_filter)
	if sz <= 0 {
		sz = 1
	}
	n := strings.clone(a.setup_filter[:len(a.setup_filter) - sz])
	delete(a.setup_filter)
	a.setup_filter = n
}

@(private)
setup_model_backspace :: proc(a: ^App) {
	if len(a.setup_model) == 0 {
		return
	}
	_, sz := utf8.decode_last_rune_in_string(a.setup_model)
	if sz <= 0 {
		sz = 1
	}
	n := strings.clone(a.setup_model[:len(a.setup_model) - sz])
	delete(a.setup_model)
	a.setup_model = n
}

@(private)
setup_filter_insert :: proc(a: ^App, ch: rune) {
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	strings.write_string(&b, a.setup_filter)
	strings.write_rune(&b, ch)
	nstr := strings.clone(strings.to_string(b))
	delete(a.setup_filter)
	a.setup_filter = nstr
	if len(a.setup_models) == 0 {
		b2: strings.Builder
		strings.builder_init(&b2, context.temp_allocator)
		strings.write_string(&b2, a.setup_model)
		strings.write_rune(&b2, ch)
		mstr := strings.clone(strings.to_string(b2))
		delete(a.setup_model)
		a.setup_model = mstr
	}
}

@(private)
setup_effort_nudge :: proc(a: ^App, delta: int) {
	if !a.setup_thinking_on {
		return
	}
	effs := setup_reason_efforts(a)
	idx := 0
	for e, i in effs {
		if e == a.setup_effort {
			idx = i
			break
		}
	}
	idx = clamp(idx + delta, 0, len(effs) - 1)
	delete(a.setup_effort)
	a.setup_effort = strings.clone(effs[idx])
	app_mark_dirty(a)
}
