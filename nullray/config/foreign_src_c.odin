// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Foreign scanners: goose, aider, aichat, llm.
*/

package config

import "core:os"
import "core:strings"
import "nullray:constants"

// goose keeps provider/model in config.yaml and file-stored secrets in a flat
// secrets.yaml. Keyring secrets are unreachable by design and get a note.
@(private)
foreign_scan_goose :: proc(scan: ^Foreign_Scan) {
	tool := "goose"
	dirs := make([dynamic]string, context.temp_allocator)
	if d := foreign_xdg_config(); len(d) > 0 {
		append(&dirs, foreign_join(d, "goose"))
		when ODIN_OS == .Windows {
			append(&dirs, foreign_join(d, "Block", "goose", "config"))
		}
	}
	dir := ""
	for d in dirs {
		if _, _, ok := foreign_read(foreign_join(d, "config.yaml")); ok {
			dir = d
			break
		}
	}
	if len(dir) == 0 {
		return
	}

	secrets := foreign_join(dir, "secrets.yaml")
	if body, mtime, ok := foreign_read(secrets); ok {
		src := foreign_disp(secrets)
		pairs := make([dynamic]Env_KV, context.temp_allocator)
		yaml_flat_map(body, &pairs)
		for kv in pairs {
			if !foreign_adoptable_env(kv.key) {
				continue
			}
			val := kv.val
			if foreign_env_is_secret(kv.key) {
				val = foreign_resolve_value(val)
			}
			hint_push(&scan.hints, tool, src, kv.key, val,
				foreign_env_is_secret(kv.key), 0, mtime)
		}
	}

	cfg := foreign_join(dir, "config.yaml")
	body, mtime, ok := foreign_read(cfg)
	if !ok {
		return
	}
	src := foreign_disp(cfg)
	prov := yaml_scalar(body, "active_provider")
	if len(prov) == 0 {
		prov = yaml_scalar(body, "GOOSE_PROVIDER")
	}
	if len(prov) == 0 {
		prov = yaml_scalar(body, "goose_provider")
	}
	model := yaml_scalar(body, "active_model")
	if len(model) == 0 {
		model = yaml_scalar(body, "GOOSE_MODEL")
	}
	if len(model) == 0 {
		model = yaml_scalar(body, "goose_model")
	}
	if len(prov) == 0 {
		return
	}
	if p, m := foreign_split_model(prov); len(p) > 0 {
		prov = p
		if len(model) == 0 {
			model = m
		}
	}
	if fp, known := foreign_provider(prov); known {
		hint_provider_model(&scan.hints, tool, src, fp.id, model, fp.key_env, mtime)
	}
}

// aider: .aider.conf.yml carries model plus api-key entries shaped
// provider=key. Only the provider that model implies gets a vote.
@(private)
foreign_scan_aider :: proc(scan: ^Foreign_Scan) {
	home := foreign_home()
	if len(home) == 0 {
		return
	}
	tool := "aider"
	path := foreign_join(home, ".aider.conf.yml")
	body, mtime, ok := foreign_read(path)
	if !ok {
		return
	}
	src := foreign_disp(path)

	if k := yaml_scalar(body, "openai-api-key"); len(k) > 0 {
		hint_push(&scan.hints, tool, src, constants.ENV_OPENAI_KEY,
			foreign_resolve_value(k), true, 0, mtime)
	}
	if k := yaml_scalar(body, "anthropic-api-key"); len(k) > 0 {
		hint_push(&scan.hints, tool, src, constants.ENV_ANTHROPIC_KEY,
			foreign_resolve_value(k), true, 0, mtime)
	}
	alts := [2]string{"openai-api-base", "openai-base-url"}
	for alt in alts {
		if b := yaml_scalar(body, alt); len(b) > 0 {
			hint_push(&scan.hints, tool, src, constants.ENV_OPENAI_BASE, b, false, 1, mtime)
			break
		}
	}
	block := yaml_block(body, "api-key")
	entries := make([dynamic]string, context.temp_allocator)
	yaml_list_scalars(block, &entries)
	if len(entries) == 0 {
		if v := yaml_scalar(body, "api-key"); len(v) > 0 {
			append(&entries, v)
		}
	}
	for e in entries {
		eq := strings.index_byte(e, '=')
		if eq <= 0 {
			continue
		}
		fp, known := foreign_provider(e[:eq])
		if !known || len(fp.key_env) == 0 {
			continue
		}
		hint_push(&scan.hints, tool, src, fp.key_env,
			foreign_resolve_value(e[eq + 1:]), true, 0, mtime)
	}

	model := yaml_scalar(body, "model")
	if len(model) == 0 {
		return
	}
	prov, bare := foreign_split_model(model)
	if len(prov) > 0 {
		model = bare
	} else {
		prov = foreign_model_provider(model)
	}
	if len(prov) == 0 {
		return
	}
	if fp, known := foreign_provider(prov); known {
		hint_provider_model(&scan.hints, tool, src, fp.id, model, fp.key_env, mtime)
	}
}

// aichat: config.yaml names the active model: client:model and a clients
// list with name/type/api_base/api_key.
@(private)
foreign_scan_aichat :: proc(scan: ^Foreign_Scan) {
	d := foreign_xdg_config()
	if len(d) == 0 {
		return
	}
	tool := "aichat"
	path := foreign_join(d, "aichat", "config.yaml")
	body, mtime, ok := foreign_read(path)
	if !ok {
		return
	}
	src := foreign_disp(path)

	sel := yaml_scalar(body, "model")
	client, model := "", ""
	if idx := strings.index_byte(sel, ':'); idx > 0 {
		client = sel[:idx]
		model = sel[idx + 1:]
	}

	clients := yaml_block(body, "clients")
	items := make([dynamic]string, context.temp_allocator)
	yaml_list_items(clients, &items)
	for item in items {
		name := yaml_kv_in(item, "name")
		typ := yaml_kv_in(item, "type")
		base := foreign_resolve_value(yaml_kv_in(item, "api_base"))
		key := foreign_resolve_value(yaml_kv_in(item, "api_key"))
		id := name
		if len(id) == 0 {
			id = typ
		}
		fp, known := foreign_provider(id)
		if known && len(fp.key_env) > 0 && len(key) > 0 {
			hint_push(&scan.hints, tool, src, fp.key_env, key, true, 0, mtime)
		}
		if len(client) > 0 && id == client {
			if known {
				hint_provider_model(&scan.hints, tool, src, fp.id, model, fp.key_env, mtime)
			} else if len(base) > 0 {
				if typ == "claude" || strings.contains(base, "anthropic") {
					hint_anthropic_endpoint(&scan.hints, tool, src, base, key, model, mtime)
				} else {
					hint_compat_provider(&scan.hints, tool, src, base, key, model, mtime)
				}
			}
		}
	}
}

// llm (datasette): keys.json is a flat alias -> key map. Aliases follow
// llm keys set names. Unknown ones are ignored.
@(private)
foreign_scan_llm :: proc(scan: ^Foreign_Scan) {
	tool := "llm"
	path := ""
	when ODIN_OS == .Darwin {
		if home := foreign_home(); len(home) > 0 {
			path = foreign_join(home, "Library", "Application Support", "io.datasette.llm", "keys.json")
		}
	} else when ODIN_OS == .Windows {
		if d := foreign_xdg_config(); len(d) > 0 {
			path = foreign_join(d, "io.datasette.llm", "keys.json")
		}
	} else {
		if d := foreign_xdg_config(); len(d) > 0 {
			path = foreign_join(d, "io.datasette.llm", "keys.json")
		}
	}
	// LLM_USER_PATH points at the whole data dir.
	if v, okv := os.lookup_env("LLM_USER_PATH", context.temp_allocator); okv && len(v) > 0 {
		path = foreign_join(v, "keys.json")
	}
	if len(path) == 0 {
		return
	}
	doc, mtime, ok := foreign_json(path)
	if !ok {
		return
	}
	src := foreign_disp(path)
	obj, _ := fj_obj(doc)
	for alias, v in obj {
		if strings.has_prefix(alias, "/") || strings.has_prefix(alias, "_") {
			continue
		}
		fp, known := foreign_provider(alias)
		if !known || len(fp.key_env) == 0 {
			continue
		}
		hint_push(&scan.hints, tool, src, fp.key_env,
			foreign_resolve_value(fj_str(v)), true, 0, mtime)
	}
}
