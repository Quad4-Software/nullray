// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
PA-Tool style tool renames (arxiv 2510.07248): a model_profiles.json entry
can pin a "tool_names" table mapping canonical tool names to the alias the
active model emits most reliably. The request path advertises the alias, and
dispatch resolves it back to the canonical name, so weak/local models stop
misaligning on the schema surface.

Guardrails: aliases must be identifier-shaped ([A-Za-z_][A-Za-z0-9_-]{0,63}),
unique, and must never collide with a registered tool name or a canonical key.
Bad entries warn once and are skipped, the mapping stays total: every emitted
alias round-trips to a real tool. NULLRAY_TOOL_RENAME=0 disables the feature.
*/

package tools

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "nullray:constants"
import "nullray:provider"

@(private)
g_alias_mu: sync.Mutex
// Active dispatch map, alias -> canonical, merged from every table the
// request path has advertised this run. Heap keys outlive callers.
@(private)
g_alias_to_canon: map[string]string
// Warn-once dedupe for skipped table entries, keyed by model|canonical|alias.
@(private)
g_alias_warned: map[string]bool
// Test hook: canonical -> alias table used instead of the profile lookup.
@(private)
g_alias_table_override: map[string]string

// NULLRAY_TOOL_RENAME=0|off|false|no disables aliasing entirely.
tool_rename_enabled :: proc() -> bool {
	v, ok := os.lookup_env(constants.ENV_TOOL_RENAME, context.temp_allocator)
	if !ok {
		return true
	}
	switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
	case "0", "false", "no", "off", "disable", "disabled":
		return false
	}
	return true
}

// Identifier shape accepted for aliases: letter or underscore first, then
// letters, digits, underscore, or dash, at most 64 chars. Dotted provider
// prefixes and mcp: names are rejected on purpose.
tool_alias_ident_ok :: proc(s: string) -> bool {
	if len(s) == 0 || len(s) > 64 {
		return false
	}
	for c, i in s {
		ok := (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'
		if i > 0 {
			ok = ok || (c >= '0' && c <= '9') || c == '-'
		}
		if !ok {
			return false
		}
	}
	return true
}

// Model used for alias lookup when the caller did not pin one: explicit arg,
// then NULLRAY_MODEL, then the last model seen by provider.profile_for
// (which the agent turn refreshes right before building tools JSON).
@(private)
tool_alias_model :: proc(explicit: string) -> string {
	if len(explicit) > 0 {
		return explicit
	}
	if v, ok := os.lookup_env(constants.ENV_MODEL, context.temp_allocator); ok && len(strings.trim_space(v)) > 0 {
		return strings.trim_space(v)
	}
	return provider.profile_last_model()
}

@(private)
tool_alias_warn_once :: proc(model, canonical, alias, reason: string) {
	key := strings.concatenate({model, "|", canonical, "|", alias, "|", reason}, context.temp_allocator)
	sync.mutex_lock(&g_alias_mu)
	seen := g_alias_warned != nil && g_alias_warned[key]
	if !seen {
		if g_alias_warned == nil {
			g_alias_warned = make(map[string]bool, runtime.heap_allocator())
		}
		g_alias_warned[strings.clone(key, runtime.heap_allocator())] = true
	}
	sync.mutex_unlock(&g_alias_mu)
	if !seen {
		fmt.eprintf("nullray: tool_names (%s): skipping %s -> %s (%s)\n", model, canonical, alias, reason)
	}
}

/*
Validated canonical -> alias table for one model. Entries whose canonical is
not a registered tool, whose alias is malformed, duplicated, or collides with
a real tool name are warned about once and skipped, so what remains always
round-trips. The returned map lives on the passed allocator.
*/
tool_alias_table :: proc(r: ^Registry, provider_id := "", model := "", allocator := context.allocator) -> map[string]string {
	out := make(map[string]string, allocator)
	if !tool_rename_enabled() {
		return out
	}
	raw: map[string]string
	key := model
	sync.mutex_lock(&g_alias_mu)
	raw = g_alias_table_override
	sync.mutex_unlock(&g_alias_mu)
	if raw == nil {
		key = tool_alias_model(model)
		if len(key) > 0 {
			if prof, ok := provider.profile_for(key); ok && len(prof.tool_names) > 0 {
				raw = prof.tool_names
			}
		}
		// Per-provider fallback: a profile globbed on the provider id itself
		// (eg "ollama") covers sessions where the model id never surfaced.
		if raw == nil && len(provider_id) > 0 {
			if prof, ok := provider.profile_for(provider_id); ok && len(prof.tool_names) > 0 {
				raw = prof.tool_names
				key = provider_id
			}
		}
	}
	if raw == nil {
		return out
	}
	for canonical, alias in raw {
		if _, ok := registry_find_exact(r, canonical); !ok {
			tool_alias_warn_once(key, canonical, alias, "canonical is not a registered tool")
			continue
		}
		if alias == canonical {
			continue
		}
		if !tool_alias_ident_ok(alias) {
			tool_alias_warn_once(key, canonical, alias, "alias is not a valid identifier")
			continue
		}
		if _, ok := registry_find_exact(r, alias); ok {
			tool_alias_warn_once(key, canonical, alias, "alias collides with a real tool name")
			continue
		}
		dup := false
		for _, other in out {
			if other == alias {
				dup = true
			}
		}
		if dup {
			tool_alias_warn_once(key, canonical, alias, "alias already maps another tool")
			continue
		}
		out[strings.clone(canonical, allocator)] = strings.clone(alias, allocator)
	}
	return out
}

// Merge a canonical -> alias table into the active dispatch map so every
// advertised alias resolves back to its tool for the rest of the run.
tool_alias_activate :: proc(table: map[string]string) {
	if len(table) == 0 {
		return
	}
	sync.mutex_lock(&g_alias_mu)
	defer sync.mutex_unlock(&g_alias_mu)
	if g_alias_to_canon == nil {
		g_alias_to_canon = make(map[string]string, runtime.heap_allocator())
	}
	for canonical, alias in table {
		if old, ok := g_alias_to_canon[alias]; ok {
			if old == canonical {
				continue
			}
			delete(old, runtime.heap_allocator())
			g_alias_to_canon[alias] = strings.clone(canonical, runtime.heap_allocator())
		} else {
			g_alias_to_canon[strings.clone(alias, runtime.heap_allocator())] = strings.clone(canonical, runtime.heap_allocator())
		}
	}
}

// Canonical name for an alias currently in the active dispatch map, ok=false
// when name is not an advertised alias. Renames off short-circuits.
tool_alias_resolve :: proc(name: string) -> (string, bool) {
	if !tool_rename_enabled() {
		return "", false
	}
	sync.mutex_lock(&g_alias_mu)
	defer sync.mutex_unlock(&g_alias_mu)
	if g_alias_to_canon == nil {
		return "", false
	}
	canon, ok := g_alias_to_canon[name]
	return canon, ok
}

// Canonical form when name is an active alias, otherwise name unchanged.
tool_alias_canonical :: proc(name: string) -> string {
	if canon, ok := tool_alias_resolve(name); ok {
		return canon
	}
	return name
}

// Test hooks: pin a canonical -> alias table and clear all alias state.
tool_alias_install_for_test :: proc(table: map[string]string) {
	sync.mutex_lock(&g_alias_mu)
	defer sync.mutex_unlock(&g_alias_mu)
	g_alias_table_override = table
}

tool_alias_reset_for_test :: proc() {
	sync.mutex_lock(&g_alias_mu)
	defer sync.mutex_unlock(&g_alias_mu)
	g_alias_table_override = nil
	for k, v in g_alias_to_canon {
		delete(k, runtime.heap_allocator())
		delete(v, runtime.heap_allocator())
	}
	delete(g_alias_to_canon)
	g_alias_to_canon = nil
	for k in g_alias_warned {
		delete(k, runtime.heap_allocator())
	}
	delete(g_alias_warned)
	g_alias_warned = nil
}
