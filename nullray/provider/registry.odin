/*
Provider registry for lookup and extension.
*/

package provider

import "core:os"
import "core:strings"
import "nullray:constants"

Registry :: struct {
	providers: [dynamic]Provider,
	active:    int,
}

registry_init :: proc(r: ^Registry) {
	r^ = {}
	r.providers = make([dynamic]Provider)
	registry_register(r, make_ollama())
	registry_register(r, make_lmstudio())
	registry_register(r, make_openai())
	registry_register(r, make_openai_compat())
	registry_register(r, make_openrouter())
	registry_register(r, make_opencode())
	registry_register(r, make_opencode_go())
	registry_register(r, make_anthropic())
	registry_register(r, make_gemini())
	registry_register(r, make_groq())
	registry_register(r, make_deepseek())
	registry_register(r, make_mistral())
	registry_register(r, make_together())
	registry_register(r, make_fireworks())
	registry_register(r, make_xai())
	registry_register(r, make_azure())
	registry_select_from_env(r)
}

registry_destroy :: proc(r: ^Registry) {
	for &p in r.providers {
		provider_destroy(&p)
	}
	delete(r.providers)
	r^ = {}
}

registry_register :: proc(r: ^Registry, p: Provider) {
	for existing, i in r.providers {
		if existing.id == p.id {
			provider_destroy(&r.providers[i])
			r.providers[i] = p
			return
		}
	}
	append(&r.providers, p)
}

registry_find :: proc(r: ^Registry, id: string) -> (^Provider, bool) {
	for &p in r.providers {
		if p.id == id {
			return &p, true
		}
	}
	return nil, false
}

registry_active :: proc(r: ^Registry) -> ^Provider {
	if len(r.providers) == 0 {
		return nil
	}
	if r.active < 0 || r.active >= len(r.providers) {
		r.active = 0
	}
	return &r.providers[r.active]
}

registry_set_active :: proc(r: ^Registry, id: string) -> bool {
	want := normalize_provider_id(id)
	for p, i in r.providers {
		if p.id == want {
			r.active = i
			return true
		}
	}
	return false
}

normalize_provider_id :: proc(id: string, allocator := context.temp_allocator) -> string {
	s := strings.to_lower(strings.trim_space(id), allocator)
	switch s {
	case "openai_compatible", "openai-compatible", "compatible", "custom":
		return "openai-compat"
	case "oai":
		return "openai"
	case "claude":
		return "anthropic"
	case "google", "google-gemini":
		return "gemini"
	case "azure-openai", "azure_openai":
		return "azure"
	case "grok":
		return "xai"
	}
	return s
}

registry_cycle :: proc(r: ^Registry, delta: int) {
	n := len(r.providers)
	if n == 0 {
		return
	}
	r.active = (r.active + delta) % n
	if r.active < 0 {
		r.active += n
	}
}

registry_select_from_env :: proc(r: ^Registry) {
	if id, ok := os.lookup_env(constants.ENV_PROVIDER, context.temp_allocator); ok {
		_ = registry_set_active(r, id)
	}
	p := registry_active(r)
	if p == nil {
		return
	}
	if model, ok := os.lookup_env(constants.ENV_MODEL, context.temp_allocator); ok && len(model) > 0 {
		delete(p.default_model)
		p.default_model = strings.clone(model)
	}
	if base, ok := os.lookup_env(constants.ENV_BASE_URL, context.temp_allocator); ok && len(base) > 0 {
		delete(p.base_url)
		p.base_url = strings.clone(normalize_openai_base(base))
	}
	if key, ok := os.lookup_env(constants.ENV_API_KEY, context.temp_allocator); ok && len(key) > 0 {
		if len(p.api_key) == 0 {
			p.api_key = strings.clone(key)
		}
	}
	if (p.id == "openai" || p.id == "openai-compat") && len(p.api_key) == 0 {
		if key, ok := os.lookup_env(constants.ENV_OPENAI_KEY, context.temp_allocator); ok && len(key) > 0 {
			p.api_key = strings.clone(key)
		}
	}
}
