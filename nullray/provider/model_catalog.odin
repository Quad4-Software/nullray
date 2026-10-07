// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Model catalog for the /model suggestion list. registry_active notes the
current provider, the /models worker records the last live fetch, and
catalog_view merges both with the models.dev cache so completion has
candidates even before the first successful fetch.
*/

package provider

import "base:runtime"
import "core:strings"
import "core:sync"

Catalog_View :: struct {
	provider_id: string,
	current:     string,
	ids:         []string,
}

@(private)
g_cat_provider:    string

@(private)
g_cat_current:     string

@(private)
g_cat_fetched_for: string

@(private)
g_cat_fetched:     [dynamic]string

@(private)
g_cat_mu:          sync.Mutex

@(private)
catalog_set_str :: proc(dst: ^string, src: string) {
	if dst^ == src {
		return
	}
	delete(dst^)
	dst^ = strings.clone(src, runtime.heap_allocator())
}

// Record which provider the UI would target. Fetched ids from a previous
// provider are dropped so suggestions never cross providers.
catalog_note_active :: proc(p: ^Provider) {
	if p == nil {
		return
	}
	sync.mutex_lock(&g_cat_mu)
	defer sync.mutex_unlock(&g_cat_mu)
	if g_cat_provider != p.id {
		catalog_set_str(&g_cat_provider, p.id)
		catalog_set_str(&g_cat_fetched_for, "")
		for id in g_cat_fetched {
			delete(id)
		}
		clear(&g_cat_fetched)
	}
	catalog_set_str(&g_cat_current, p.default_model)
}

// Store the ids a live list_models returned, tagged by provider so a stale
// worker result cannot leak into another provider's suggestions.
catalog_store :: proc(provider_id: string, models: []Model_Info) {
	if len(provider_id) == 0 {
		return
	}
	sync.mutex_lock(&g_cat_mu)
	defer sync.mutex_unlock(&g_cat_mu)
	catalog_set_str(&g_cat_fetched_for, provider_id)
	for id in g_cat_fetched {
		delete(id)
	}
	clear(&g_cat_fetched)
	for m in models {
		if len(m.id) > 0 {
			append(&g_cat_fetched, strings.clone(m.id, runtime.heap_allocator()))
		}
	}
}

/*
Merged candidates for the active provider: current model first, then the last
live fetch, then any extra models.dev ids. Reads both catalogs under their own
locks, never nested.
*/
catalog_view :: proc(allocator := context.temp_allocator) -> Catalog_View {
	view: Catalog_View
	sync.mutex_lock(&g_cat_mu)
	pid := strings.clone(g_cat_provider, context.temp_allocator)
	view.provider_id = strings.clone(g_cat_provider, allocator)
	view.current = strings.clone(g_cat_current, allocator)
	seen := make(map[string]bool, context.temp_allocator)
	out := make([dynamic]string, 0, 32, allocator)
	if len(view.current) > 0 {
		seen[view.current] = true
		append(&out, view.current)
	}
	if g_cat_fetched_for == pid {
		for id in g_cat_fetched {
			if id not_in seen {
				seen[id] = true
				append(&out, strings.clone(id, allocator))
			}
		}
	}
	sync.mutex_unlock(&g_cat_mu)
	for id in modelsdev_ids(pid, context.temp_allocator) {
		if id not_in seen {
			append(&out, strings.clone(id, allocator))
		}
	}
	view.ids = out[:]
	return view
}

catalog_view_destroy :: proc(view: ^Catalog_View) {
	delete(view.provider_id)
	delete(view.current)
	for id in view.ids {
		delete(id)
	}
	delete(view.ids)
	view^ = {}
}

// Frees catalog state. Tests use this; the runtime catalog lives for the
// process lifetime.
catalog_reset :: proc() {
	sync.mutex_lock(&g_cat_mu)
	defer sync.mutex_unlock(&g_cat_mu)
	delete(g_cat_provider)
	delete(g_cat_current)
	delete(g_cat_fetched_for)
	for id in g_cat_fetched {
		delete(id)
	}
	delete(g_cat_fetched)
	g_cat_provider = ""
	g_cat_current = ""
	g_cat_fetched_for = ""
	g_cat_fetched = make([dynamic]string)
}
