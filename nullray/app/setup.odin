// SPDX-License-Identifier: 0BSD
/*
TUI-only setup overlay. Prefer /setup. Auto-opens when setup_needed.
Never used from --print or --self-test.
*/

package app

import "core:os"
import "core:strings"
import "nullray:config"
import "nullray:constants"
import "nullray:provider"

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
