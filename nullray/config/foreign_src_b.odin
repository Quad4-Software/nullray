// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Foreign scanners: OpenAI Codex, Gemini CLI, Qwen Code, Crush.
*/

package config

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"
import "nullray:constants"

@(private)
foreign_scan_codex :: proc(scan: ^Foreign_Scan) {
	home := ""
	if v, ok := os.lookup_env("CODEX_HOME", context.temp_allocator); ok && len(v) > 0 {
		home = v
	} else {
		base := foreign_home()
		if len(base) == 0 {
			return
		}
		home = foreign_join(base, ".codex")
	}
	tool := "codex"

	auth := foreign_join(home, "auth.json")
	if doc, mtime, ok := foreign_json(auth); ok {
		src := foreign_disp(auth)
		hint_push(&scan.hints, tool, src, constants.ENV_OPENAI_KEY,
			foreign_resolve_value(fj_str(fj_get(doc, "OPENAI_API_KEY"))), true, 0, mtime)
		if len(fj_str(fj_dig(doc, "tokens", "access_token"))) > 0 {
			note_push(&scan.notes, tool, "ChatGPT account tokens in auth.json are not importable")
		}
	}

	cfg := foreign_join(home, "config.toml")
	body, mtime, ok := foreign_read(cfg)
	if !ok {
		return
	}
	src := foreign_disp(cfg)
	root := toml_root(body)
	model := toml_value_in(root, "model")
	prov := toml_value_in(root, "model_provider")
	if base := toml_value_in(root, "openai_base_url"); len(base) > 0 {
		hint_push(&scan.hints, tool, src, constants.ENV_OPENAI_BASE, base, false, 1, mtime)
	}
	if len(prov) == 0 || prov == "openai" {
		hint_provider_model(&scan.hints, tool, src, "openai", model,
			constants.ENV_OPENAI_KEY, mtime)
		return
	}
	for sec in toml_sections(body, "model_providers") {
		if sec.name != prov {
			continue
		}
		base := toml_value_in(sec.body, "base_url")
		if len(base) == 0 {
			return
		}
		if toml_value_in(sec.body, "wire_api") == "responses" {
			note_push(&scan.notes, tool,
				fmt.tprintf("provider %s uses the responses API; nullray speaks chat/completions", prov))
			return
		}
		key := ""
		if env_key := toml_value_in(sec.body, "env_key"); len(env_key) > 0 {
			if v, ok := os.lookup_env(env_key, context.temp_allocator); ok {
				key = v
			}
		}
		hint_compat_provider(&scan.hints, tool, src, base, key, model, mtime)
		return
	}
	// Unknown provider id with no section: no usable connection info.
}

@(private)
foreign_scan_gemini :: proc(scan: ^Foreign_Scan) {
	home := foreign_home()
	if len(home) == 0 {
		return
	}
	dir := foreign_join(home, ".gemini")
	tool := "gemini-cli"

	env_path := foreign_join(dir, ".env")
	if body, mtime, ok := foreign_read(env_path); ok {
		src := foreign_disp(env_path)
		pairs := make([dynamic]Env_KV, context.temp_allocator)
		foreign_dotenv_pairs(body, &pairs)
		for kv in pairs {
			if !foreign_adoptable_env(kv.key) {
				continue
			}
			hint_push(&scan.hints, tool, src, kv.key, kv.val,
				foreign_env_is_secret(kv.key), 0, mtime)
		}
	}

	settings := foreign_join(dir, "settings.json")
	if doc, mtime, ok := foreign_json(settings); ok {
		src := foreign_disp(settings)
		kind := fj_str(fj_dig(doc, "security", "auth", "selectedType"))
		model := fj_str(fj_dig(doc, "model", "name"))
		if len(model) == 0 {
			model = fj_str(fj_get(doc, "model"))
		}
		switch kind {
		case "gemini-api-key", "":
			hint_provider_model(&scan.hints, tool, src, "gemini", model,
				constants.ENV_GEMINI_KEY, mtime)
		case "oauth-personal", "compute-adc", "cloud-shell":
			note_push(&scan.notes, tool, fmt.tprintf("auth type %s is not importable", kind))
		}
	}
	if _, _, ok := foreign_read(foreign_join(dir, "oauth_creds.json")); ok {
		note_push(&scan.notes, tool, "oauth_creds.json present; Google OAuth needs a token exchange, not imported")
	}
}

// Qwen Code stores real keys in settings.json env and picks a protocol via
// security.auth.selectedType. modelProviders.<proto>[] entries carry
// baseUrl and the envKey holding the credential.
@(private)
foreign_scan_qwen :: proc(scan: ^Foreign_Scan) {
	home := foreign_home()
	if len(home) == 0 {
		return
	}
	dir := foreign_join(home, ".qwen")
	tool := "qwen-code"

	env_path := foreign_join(dir, ".env")
	if body, mtime, ok := foreign_read(env_path); ok {
		src := foreign_disp(env_path)
		pairs := make([dynamic]Env_KV, context.temp_allocator)
		foreign_dotenv_pairs(body, &pairs)
		for kv in pairs {
			if !foreign_adoptable_env(kv.key) {
				continue
			}
			hint_push(&scan.hints, tool, src, kv.key, kv.val,
				foreign_env_is_secret(kv.key), 0, mtime)
		}
	}

	settings := foreign_join(dir, "settings.json")
	doc, mtime, ok := foreign_json(settings)
	if !ok {
		return
	}
	src := foreign_disp(settings)
	env_obj, _ := fj_obj(fj_get(doc, "env"))
	if len(env_obj) > 0 {
		foreign_adopt_env_map(scan, tool, src, env_obj, mtime)
	}
	model := fj_str(fj_dig(doc, "model", "name"))
	kind := fj_str(fj_dig(doc, "security", "auth", "selectedType"))
	if len(kind) == 0 {
		return
	}
	if kind == "qwen-oauth" {
		note_push(&scan.notes, tool, "qwen-oauth creds are not importable")
		return
	}
	provs, _ := fj_obj(fj_get(doc, "modelProviders"))
	arr, _ := provs[kind].(json.Array)
	entry := json.Object{}
	for item in arr {
		obj, ook := fj_obj(item)
		if !ook {
			continue
		}
		if len(entry) == 0 || fj_str(obj["id"]) == model {
			entry = obj
		}
	}
	base := foreign_resolve_value(fj_str(entry["baseUrl"]))
	key := ""
	if env_key := fj_str(entry["envKey"]); len(env_key) > 0 {
		if v, eok := env_obj[env_key]; eok {
			key = foreign_resolve_value(fj_str(v))
		}
		if len(key) == 0 {
			if v, eok := os.lookup_env(env_key, context.temp_allocator); eok {
				key = v
			}
		}
	}
	switch kind {
	case "anthropic":
		hint_anthropic_endpoint(&scan.hints, tool, src, base, key, model, mtime)
	case "gemini":
		if len(base) == 0 {
			hint_provider_model(&scan.hints, tool, src, "gemini", model,
				constants.ENV_GEMINI_KEY, mtime)
		} else {
			hint_compat_provider(&scan.hints, tool, src, base, key, model, mtime)
		}
	case:
		if len(base) > 0 && strings.contains(base, "dashscope") {
			if len(key) > 0 {
				hint_push(&scan.hints, tool, src, constants.ENV_DASHSCOPE_KEY, key, true, 0, mtime)
			}
			hint_provider_model(&scan.hints, tool, src, "dashscope", model,
				constants.ENV_DASHSCOPE_KEY, mtime)
		} else {
			hint_compat_provider(&scan.hints, tool, src, base, key, model, mtime)
		}
	}
}

// Crush providers map carries api_key ($ENV resolved) and base_url. The
// models.large pair picks the active provider.
@(private)
foreign_scan_crush :: proc(scan: ^Foreign_Scan) {
	d := foreign_xdg_config()
	if len(d) == 0 {
		return
	}
	path := foreign_join(d, "crush", "crush.json")
	doc, mtime, ok := foreign_json(path)
	if !ok {
		return
	}
	tool := "crush"
	src := foreign_disp(path)

	providers, _ := fj_obj(fj_get(doc, "providers"))
	for pid, pv in providers {
		pobj, _ := fj_obj(pv)
		key := foreign_resolve_value(fj_str(pobj["api_key"]))
		if len(key) == 0 {
			continue
		}
		if fp, known := foreign_provider(pid); known && len(fp.key_env) > 0 {
			hint_push(&scan.hints, tool, src, fp.key_env, key, true, 0, mtime)
		}
	}

	large := fj_dig(doc, "models", "large")
	prov := fj_str(fj_get(large, "provider"))
	model := fj_str(fj_get(large, "model"))
	if len(prov) == 0 {
		prov, model = foreign_split_model(fj_str(fj_get(doc, "model")))
	}
	if len(prov) == 0 {
		return
	}
	if fp, known := foreign_provider(prov); known {
		// A known provider can still carry a proxy base_url in crush config.
		pobj, _ := fj_obj(providers[prov])
		base := foreign_resolve_value(fj_str(pobj["base_url"]))
		if len(base) > 0 {
			switch fp.id {
			case "anthropic":
				hint_push(&scan.hints, tool, src, constants.ENV_ANTHROPIC_BASE, base, false, 3, mtime,
					require_env = constants.ENV_PROVIDER, require_val = "anthropic")
			case "openai", "openai-compat":
				hint_push(&scan.hints, tool, src, constants.ENV_OPENAI_BASE, base, false, 1, mtime)
			case:
				// No per-vendor base env exists: keep the key off the real
				// vendor host by voting openai-compat instead.
				hint_compat_provider(&scan.hints, tool, src, base,
					fj_str(pobj["api_key"]), model, mtime)
				return
			}
		}
		hint_provider_model(&scan.hints, tool, src, fp.id, model, fp.key_env, mtime)
		return
	}
	pobj, pok := fj_obj(providers[prov])
	if !pok {
		return
	}
	base := foreign_resolve_value(fj_str(pobj["base_url"]))
	key := fj_str(pobj["api_key"])
	if fj_str(pobj["type"]) == "anthropic" {
		hint_anthropic_endpoint(&scan.hints, tool, src, base, key, model, mtime)
		return
	}
	hint_compat_provider(&scan.hints, tool, src, base, key, model, mtime)
}
