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
	registry_register(r, make_openrouter())
	registry_register(r, make_opencode())
	registry_register(r, make_opencode_go())
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
	for p, i in r.providers {
		if p.id == id {
			r.active = i
			return true
		}
	}
	return false
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
		_ = registry_set_active(r, strings.to_lower(id, context.temp_allocator))
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
		p.base_url = strings.clone(base)
	}
	if key, ok := os.lookup_env(constants.ENV_API_KEY, context.temp_allocator); ok && len(key) > 0 {
		if len(p.api_key) == 0 {
			p.api_key = strings.clone(key)
		}
	}
}
