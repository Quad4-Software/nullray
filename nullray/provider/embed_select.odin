// SPDX-License-Identifier: 0BSD
/*
Resolve embed provider and model separate from chat.
*/

package provider

import "core:os"
import "core:strings"
import "nullray:constants"

/*
Pick embed provider from env, else chat provider when local, else first live local,
else openrouter when keyed. Caller must provider_destroy owned copies from make_*.
Returns a pointer into reg when found there. When owned is true, caller owns p.
*/
resolve_embed_provider :: proc(
	reg: ^Registry,
	chat: ^Provider,
	allocator := context.allocator,
) -> (
	p: ^Provider,
	owned: bool,
	err: string,
) {
	_ = allocator
	if id, ok := os.lookup_env(constants.ENV_EMBED_PROVIDER, context.temp_allocator); ok {
		want := normalize_provider_id(strings.trim_space(id))
		if len(want) > 0 {
			if reg != nil {
				if found, fok := registry_find(reg, want); fok {
					if found.embed == nil {
						return nil, false, strings.clone("embed provider has no embed API", allocator)
					}
					return found, false, ""
				}
			}
			made, mok := make_provider_by_id(want)
			if !mok {
				return nil, false, strings.clone("unknown NULLRAY_EMBED_PROVIDER", allocator)
			}
			if made.embed == nil {
				provider_destroy(&made)
				return nil, false, strings.clone("embed provider has no embed API", allocator)
			}
			heap := new(Provider, allocator)
			heap^ = made
			return heap, true, ""
		}
	}
	if chat != nil && chat.embed != nil && provider_is_local(chat.id) {
		return chat, false, ""
	}
	if reg != nil && local_probe_enabled_from_env() {
		for lid in LOCAL_PROBE_IDS {
			if found, fok := registry_find(reg, lid); fok && found.embed != nil {
				if probe_local_provider(lid, 2) {
					return found, false, ""
				}
			}
		}
	}
	if chat != nil && chat.embed != nil {
		return chat, false, ""
	}
	if reg != nil {
		if found, fok := registry_find(reg, "openrouter"); fok && found.embed != nil {
			if len(found.api_key) > 0 {
				return found, false, ""
			}
		}
	}
	return nil, false, strings.clone("no embed provider available", allocator)
}

resolve_embed_model :: proc(p: ^Provider) -> string {
	if p == nil {
		return ""
	}
	return default_embed_model_for_provider(p.id)
}

provider_embed_texts :: proc(
	p: ^Provider,
	model: string,
	inputs: []string,
	allocator := context.allocator,
) -> Embed_Response {
	if p == nil || p.embed == nil {
		return Embed_Response{ok = false, err = strings.clone("embed not supported", allocator)}
	}
	m := model
	if len(m) == 0 {
		m = resolve_embed_model(p)
	}
	return p.embed(p, Embed_Request{model = m, input = inputs}, allocator)
}
