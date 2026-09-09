// SPDX-License-Identifier: 0BSD
/*
Setup wizard flow: models, reasoning, advance, save.
*/

package app

import "core:fmt"
import "core:os"
import "core:strings"
import "nullray:config"
import "nullray:constants"
import "nullray:provider"
import "nullray:session"

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
