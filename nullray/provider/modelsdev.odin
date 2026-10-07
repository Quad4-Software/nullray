// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
models.dev catalog cache. api.json is the same model metadata schema the
OpenCode v2 catalog serves (family, capabilities, npm package, limits, cost).
Cached under the config dir with a TTL, refreshes from /models and friends.
Chat routing reads the cache only and never blocks on the network.
*/

package provider

import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "core:sync"
import "core:time"
import "nullray:constants"
import "nullray:http"
import "nullray:sandbox"

Modelsdev_Meta :: struct {
	context_limit: int,
	output_limit:  int,
	cost_in:       f64,
	cost_out:      f64,
	has_cost:      bool,
}

@(private)
g_md_loaded: bool

@(private)
g_md_mtime: time.Time

@(private)
g_md_npm: map[string]string

@(private)
g_md_meta: map[string]Modelsdev_Meta

// Every pid/mid key seen in the cache, including models with no meta.
@(private)
g_md_all: map[string]bool

@(private)
g_md_mu: sync.Mutex

@(private)
modelsdev_enabled :: proc() -> bool {
	if v, ok := os.lookup_env(constants.ENV_MODELSDEV, context.temp_allocator); ok {
		switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
		case "0", "false", "off", "no":
			return false
		}
	}
	return true
}

modelsdev_path :: proc(allocator := context.allocator) -> string {
	dir := sandbox.resolve_config_dir(context.temp_allocator)
	p, _ := filepath.join({dir, constants.MODELSDEV_FILE}, allocator)
	return p
}

@(private)
modelsdev_key :: proc(provider_id, model: string, allocator := context.temp_allocator) -> string {
	return strings.concatenate({provider_id, "/", model}, allocator)
}

@(private)
modelsdev_clear_locked :: proc() {
	for k, v in g_md_npm {
		delete(k, runtime.heap_allocator())
		delete(v, runtime.heap_allocator())
	}
	delete(g_md_npm)
	for k in g_md_meta {
		delete(k, runtime.heap_allocator())
	}
	delete(g_md_meta)
	for k in g_md_all {
		delete(k, runtime.heap_allocator())
	}
	delete(g_md_all)
	g_md_npm = nil
	g_md_meta = nil
	g_md_all = nil
	g_md_loaded = false
}

@(private)
modelsdev_float_field :: proc(obj: json.Object, key: string) -> (f64, bool) {
	return json_float_field_ok(obj, key)
}

@(private)
modelsdev_parse_locked :: proc(path: string, mtime: time.Time) {
	data, rerr := os.read_entire_file(path, context.temp_allocator)
	if rerr != nil || len(data) == 0 {
		return
	}
	temp_epoch := runtime.default_temp_allocator_temp_begin()
	defer runtime.default_temp_allocator_temp_end(temp_epoch)
	doc, perr := json.parse_string(string(data), .JSON, allocator = context.temp_allocator)
	if perr != .None {
		return
	}
	root, rok := doc.(json.Object)
	if !rok {
		return
	}
	npm_map := make(map[string]string, 0, runtime.heap_allocator())
	meta_map := make(map[string]Modelsdev_Meta, 0, runtime.heap_allocator())
	all_map := make(map[string]bool, 0, runtime.heap_allocator())
	for pid, pv in root {
		pobj, pok := pv.(json.Object)
		if !pok {
			continue
		}
		mv, mok := pobj["models"]
		mobj, mmok := mv.(json.Object)
		if !mok || !mmok {
			continue
		}
		for mid, mvv in mobj {
			mo, mo_ok := mvv.(json.Object)
			if !mo_ok {
				continue
			}
			key := modelsdev_key(pid, mid)
			if key not_in all_map {
				all_map[strings.clone(key, runtime.heap_allocator())] = true
			}
			if pv2, p2ok := mo["provider"]; p2ok {
				if pobj2, ppok := pv2.(json.Object); ppok {
					if nv, nok := pobj2["npm"]; nok {
						if s, sok := nv.(json.String); sok {
							npm_map[strings.clone(key, runtime.heap_allocator())] = strings.clone(string(s), runtime.heap_allocator())
						}
					}
				}
			}
			meta: Modelsdev_Meta
			got := false
			if lv, lok := mo["limit"]; lok {
				if lobj, llok := lv.(json.Object); llok {
					meta.context_limit = json_int_field(lobj, "context")
					meta.output_limit = json_int_field(lobj, "output")
					got = meta.context_limit > 0 || meta.output_limit > 0
				}
			}
			if cv, cok := mo["cost"]; cok {
				if cobj, ccok := cv.(json.Object); ccok {
					if ci, ciok := modelsdev_float_field(cobj, "input"); ciok {
						meta.cost_in = ci
						meta.has_cost = true
					}
					if co, cook := modelsdev_float_field(cobj, "output"); cook {
						meta.cost_out = co
						meta.has_cost = true
					}
					got = got || meta.has_cost
				}
			}
			if got {
				meta_map[strings.clone(key, runtime.heap_allocator())] = meta
			}
		}
	}
	modelsdev_clear_locked()
	g_md_npm = npm_map
	g_md_meta = meta_map
	g_md_all = all_map
	g_md_mtime = mtime
	g_md_loaded = true
}

// Reload the parsed maps when the cache file changed on disk.
modelsdev_ensure :: proc() {
	if !modelsdev_enabled() {
		return
	}
	path := modelsdev_path(context.temp_allocator)
	fi, ferr := os.stat(path, context.temp_allocator)
	if ferr != nil {
		return
	}
	sync.mutex_lock(&g_md_mu)
	defer sync.mutex_unlock(&g_md_mu)
	if g_md_loaded && fi.modification_time == g_md_mtime {
		return
	}
	modelsdev_parse_locked(path, fi.modification_time)
}

// Download the catalog into the config dir. Returns "" on success.
modelsdev_refresh :: proc() -> string {
	if !modelsdev_enabled() {
		return "models.dev catalog disabled (NULLRAY_MODELSDEV=0)"
	}
	res := http.get_max(
		constants.MODELSDEV_URL,
		nil,
		constants.MODELSDEV_FETCH_TIMEOUT_SEC,
		constants.MODELSDEV_MAX_BYTES,
		context.temp_allocator,
	)
	if !res.ok {
		return res.err
	}
	// Validate before replacing a good cache with a mangled body.
	doc, perr := json.parse_string(res.body, .JSON, allocator = context.temp_allocator)
	if perr != .None {
		return "models.dev returned bad JSON"
	}
	root, rok := doc.(json.Object)
	if !rok || len(root) == 0 {
		return "models.dev returned empty catalog"
	}
	path := modelsdev_path(context.temp_allocator)
	if dir := filepath.dir(path); len(dir) > 0 {
		_ = os.make_directory_all(dir)
	}
	// Write-then-rename: a torn write would poison the cache until the TTL.
	tmp := fmt.tprintf("%s.tmp", path)
	if werr := os.write_entire_file(tmp, transmute([]u8)res.body); werr != nil {
		return "models.dev cache write failed"
	}
	if rerr := os.rename(tmp, path); rerr != nil {
		_ = os.remove(tmp)
		return "models.dev cache write failed"
	}
	sync.mutex_lock(&g_md_mu)
	modelsdev_clear_locked()
	sync.mutex_unlock(&g_md_mu)
	return ""
}

modelsdev_refresh_if_stale :: proc() {
	if !modelsdev_enabled() {
		return
	}
	path := modelsdev_path(context.temp_allocator)
	if fi, ferr := os.stat(path, context.temp_allocator); ferr == nil {
		age := time.since(fi.modification_time)
		if age < time.Duration(constants.MODELSDEV_TTL_SEC) * time.Second {
			return
		}
	}
	_ = modelsdev_refresh()
}

@(private)
modelsdev_npm :: proc(provider_id, model: string) -> string {
	modelsdev_ensure()
	sync.mutex_lock(&g_md_mu)
	defer sync.mutex_unlock(&g_md_mu)
	// Clone before unlocking: a refresh reload frees map strings.
	if v, ok := g_md_npm[modelsdev_key(modelsdev_provider_id(provider_id), model)]; ok {
		return strings.clone(v, context.temp_allocator)
	}
	return ""
}

modelsdev_model_meta :: proc(provider_id, model: string) -> (Modelsdev_Meta, bool) {
	modelsdev_ensure()
	sync.mutex_lock(&g_md_mu)
	defer sync.mutex_unlock(&g_md_mu)
	if v, ok := g_md_meta[modelsdev_key(modelsdev_provider_id(provider_id), model)]; ok {
		return v, true
	}
	return {}, false
}

// Attach catalog limits and cost to a fetched model list. No-op when the
// cache is absent or the provider is unknown to models.dev.
modelsdev_enrich :: proc(provider_id: string, models: []Model_Info) {
	if len(provider_id) == 0 || len(models) == 0 {
		return
	}
	for &m in models {
		if meta, ok := modelsdev_model_meta(provider_id, m.id); ok {
			m.context_limit = meta.context_limit
			m.output_limit = meta.output_limit
			m.cost_in = meta.cost_in
			m.cost_out = meta.cost_out
			m.has_cost = meta.has_cost
		}
	}
}

// Registry ids that differ from their models.dev catalog key. Parse keys stay
// as served; only lookups remap.
modelsdev_provider_id :: proc(id: string) -> string {
	switch id {
	case "gemini":
		return "google"
	case "together":
		return "togetherai"
	case "fireworks":
		return "fireworks-ai"
	case "dashscope":
		return "alibaba"
	case "ollama":
		return "ollama-cloud"
	}
	return id
}

// Every model id the cache knows for a provider, sorted. Empty when the cache
// is absent or the provider is unknown to models.dev.
modelsdev_ids :: proc(provider_id: string, allocator := context.allocator) -> []string {
	modelsdev_ensure()
	pid := modelsdev_provider_id(provider_id)
	prefix := strings.concatenate({pid, "/"}, context.temp_allocator)
	out := make([dynamic]string, 0, 32, allocator)
	sync.mutex_lock(&g_md_mu)
	for k in g_md_all {
		if strings.has_prefix(k, prefix) {
			append(&out, strings.clone(k[len(prefix):], allocator))
		}
	}
	sync.mutex_unlock(&g_md_mu)
	slice.sort_by(out[:], proc(a, b: string) -> bool { return strings.compare(a, b) < 0 })
	return out[:]
}

// Full catalog list for a provider with limits and cost attached. Used as the
// /models and --list-models fallback when no live listing endpoint answers.
modelsdev_list :: proc(provider_id: string, allocator := context.allocator) -> []Model_Info {
	ids := modelsdev_ids(provider_id, context.temp_allocator)
	if len(ids) == 0 {
		return nil
	}
	out := make([]Model_Info, len(ids), allocator)
	for id, i in ids {
		out[i] = Model_Info{
			id = strings.clone(id, allocator),
			name = strings.clone(id, allocator),
		}
	}
	modelsdev_enrich(provider_id, out)
	return out
}
