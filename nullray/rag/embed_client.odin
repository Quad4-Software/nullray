// SPDX-License-Identifier: 0BSD
/*
Embed calls for RAG ingest and query.
*/

package rag

import "core:strings"
import "nullray:provider"

embed_batch :: proc(model: string, inputs: []string, allocator := context.allocator) -> ([][]f32, string) {
	if g_embed_override != nil {
		return g_embed_override(model, inputs, allocator)
	}
	ep, owned, err := provider.resolve_embed_provider(g_provider_reg, g_chat_provider, context.temp_allocator)
	if len(err) > 0 || ep == nil {
		if owned && ep != nil {
			provider.provider_destroy(ep)
			free(ep)
		}
		if len(err) == 0 {
			err = strings.clone("no embed provider", allocator)
		}
		return nil, err
	}
	defer if owned {
		provider.provider_destroy(ep)
		free(ep)
	}
	m := model
	if len(m) == 0 {
		m = provider.resolve_embed_model(ep)
	}
	res := provider.provider_embed_texts(ep, m, inputs, allocator)
	if !res.ok {
		err2 := strings.clone(res.err, allocator)
		provider.destroy_embed_response(&res)
		return nil, err2
	}
	// Transfer ownership of vectors out of response.
	out := res.vectors
	res.vectors = nil
	provider.destroy_embed_response(&res)
	return out, ""
}

current_embed_identity :: proc(allocator := context.allocator) -> (prov, model: string, err: string) {
	if g_embed_override != nil {
		return strings.clone("test", allocator), strings.clone("fake-embed", allocator), ""
	}
	ep, owned, e := provider.resolve_embed_provider(g_provider_reg, g_chat_provider, context.temp_allocator)
	if len(e) > 0 || ep == nil {
		if owned && ep != nil {
			provider.provider_destroy(ep)
			free(ep)
		}
		return "", "", e
	}
	defer if owned {
		provider.provider_destroy(ep)
		free(ep)
	}
	return strings.clone(ep.id, allocator), strings.clone(provider.resolve_embed_model(ep), allocator), ""
}

semantic_available :: proc() -> bool {
	if rag_disabled() {
		return false
	}
	if g_embed_override != nil {
		return true
	}
	if rag_forced() {
		ep, owned, err := provider.resolve_embed_provider(g_provider_reg, g_chat_provider, context.temp_allocator)
		if owned && ep != nil {
			provider.provider_destroy(ep)
			free(ep)
		}
		return ep != nil && len(err) == 0
	}
	// auto: require override or a resolvable provider (do not probe network here)
	ep, owned, err := provider.resolve_embed_provider(g_provider_reg, g_chat_provider, context.temp_allocator)
	ok := ep != nil && len(err) == 0 && ep.embed != nil
	if owned && ep != nil {
		provider.provider_destroy(ep)
		free(ep)
	}
	return ok
}
