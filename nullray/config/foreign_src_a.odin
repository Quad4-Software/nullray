// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Foreign scanners: Claude Code, OpenCode, pi.
*/

package config

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"
import "nullray:constants"

// Adopt keys/base URLs from a settings-style env object (claude env, qwen env).
@(private)
foreign_adopt_env_map :: proc(
	scan: ^Foreign_Scan,
	tool, source: string,
	obj: json.Object,
	mtime: i64,
) {
	for key, v in obj {
		val := fj_str(v)
		if len(val) == 0 {
			continue
		}
		if key == "ANTHROPIC_MODEL" {
			hint_push(&scan.hints, tool, source, constants.ENV_MODEL, val, false, 3, mtime,
				require_env = constants.ENV_PROVIDER, require_val = "anthropic")
			continue
		}
		if !foreign_adoptable_env(key) {
			continue
		}
		val = foreign_resolve_value(val)
		hint_push(&scan.hints, tool, source, key, val, foreign_env_is_secret(key), 0, mtime)
	}
}

// Anthropic-flavored custom endpoint: vendor key env plus a base URL bound to
// the anthropic provider vote.
@(private)
hint_anthropic_endpoint :: proc(
	hints: ^[dynamic]Foreign_Hint,
	tool, source, base, key, model: string,
	mtime: i64,
) {
	k := foreign_resolve_value(key)
	if len(k) > 0 {
		hint_push(hints, tool, source, constants.ENV_ANTHROPIC_KEY, k, true, 0, mtime)
	}
	require := constants.ENV_ANTHROPIC_KEY
	if len(k) == 0 {
		// Authless Messages relay: vote can stand on its own.
		require = ""
	}
	hint_push(hints, tool, source, constants.ENV_PROVIDER, "anthropic", false, 2, mtime,
		require_env = require)
	if b := strings.trim_space(foreign_resolve_value(base)); len(b) > 0 {
		hint_push(hints, tool, source, constants.ENV_ANTHROPIC_BASE, b, false, 3, mtime,
			require_env = constants.ENV_PROVIDER, require_val = "anthropic")
	}
	if len(model) > 0 {
		hint_push(hints, tool, source, constants.ENV_MODEL, model, false, 3, mtime,
			require_env = constants.ENV_PROVIDER, require_val = "anthropic")
	}
}

// Split a "provider/model" selector into its parts.
@(private)
foreign_split_model :: proc(sel: string) -> (prov, model: string) {
	s := strings.trim_space(sel)
	if idx := strings.index_byte(s, '/'); idx > 0 {
		return s[:idx], s[idx + 1:]
	}
	return "", s
}

@(private)
foreign_scan_claude :: proc(scan: ^Foreign_Scan) {
	home := foreign_home()
	if len(home) == 0 {
		return
	}
	tool := "claude-code"
	settings := foreign_join(home, ".claude", "settings.json")
	if doc, mtime, ok := foreign_json(settings); ok {
		src := foreign_disp(settings)
		if env, eok := fj_obj(fj_get(doc, "env")); eok {
			foreign_adopt_env_map(scan, tool, src, env, mtime)
		}
		model := fj_str(fj_get(doc, "model"))
		hint_provider_model(&scan.hints, tool, src, "anthropic", model,
			constants.ENV_ANTHROPIC_KEY, mtime)
	}
	creds := foreign_join(home, ".claude", ".credentials.json")
	if doc, _, ok := foreign_json(creds); ok {
		if tok := fj_str(fj_dig(doc, "claudeAiOauth", "accessToken")); len(tok) > 0 {
			note_push(&scan.notes, tool,
				"OAuth subscription token in .credentials.json stays with Claude (needs Bearer auth, not x-api-key)")
		}
	}
}

// OpenCode auth.json is a map of models.dev provider id to api key or oauth.
@(private)
foreign_scan_opencode_auth :: proc(scan: ^Foreign_Scan, path: string) {
	doc, mtime, ok := foreign_json(path)
	if !ok {
		return
	}
	src := foreign_disp(path)
	obj, ook := fj_obj(doc)
	if !ook {
		return
	}
	for pid, entry in obj {
		eobj, eok := fj_obj(entry)
		if !eok {
			continue
		}
		fp, known := foreign_provider(pid)
		kind := fj_str(eobj["type"])
		switch kind {
		case "api":
			if !known || len(fp.key_env) == 0 {
				continue
			}
			hint_push(&scan.hints, "opencode", src, fp.key_env,
				foreign_resolve_value(fj_str(eobj["key"])), true, 0, mtime)
		case "oauth":
			// Zen accepts its own OAuth access token as the API credential.
			// third-party oauth tokens need a Bearer exchange we do not do.
			if pid == "opencode" || pid == "opencode-go" {
				hint_push(&scan.hints, "opencode", src, constants.ENV_OPENCODE_KEY,
					foreign_resolve_value(fj_str(eobj["access"])), true, 0, mtime)
			} else if len(fj_str(eobj["access"])) > 0 {
				note_push(&scan.notes, "opencode", fmt.tprintf("oauth for %s not importable", pid))
			}
		}
	}
}

// opencode.json custom provider: emit compat or anthropic chain when the
// selected model points at it.
@(private)
foreign_opencode_provider_opts :: proc(
	scan: ^Foreign_Scan,
	src, prov, model: string,
	providers: json.Object,
	mtime: i64,
) {
	pv, pok := fj_obj(providers[prov])
	if !pok {
		return
	}
	opts, _ := fj_obj(pv["options"])
	base := foreign_resolve_value(fj_str(opts["baseURL"]))
	key := fj_str(opts["apiKey"])
	npm := fj_str(pv["npm"])
	if fp, known := foreign_provider(prov); known {
		// Known provider with options: adopt inline key and custom base.
		if len(fp.key_env) > 0 {
			hint_push(&scan.hints, "opencode", src, fp.key_env,
				foreign_resolve_value(key), true, 0, mtime)
		}
		base_ok := len(strings.trim_space(base)) > 0
		if base_ok && prov != "anthropic" && prov != "openai" && npm != "@ai-sdk/anthropic" {
			// A custom base we cannot retarget per-vendor must not send the
			// key to the real vendor host: run it through openai-compat.
			hint_compat_provider(&scan.hints, "opencode", src, base, key, model, mtime)
			return
		}
		if base_ok {
			if prov == "anthropic" {
				hint_push(&scan.hints, "opencode", src, constants.ENV_ANTHROPIC_BASE, base, false, 3, mtime,
					require_env = constants.ENV_PROVIDER, require_val = "anthropic")
			} else if prov == "openai" {
				hint_push(&scan.hints, "opencode", src, constants.ENV_OPENAI_BASE, base, false, 1, mtime)
			}
		}
		hint_provider_model(&scan.hints, "opencode", src, fp.id, model, fp.key_env, mtime)
		return
	}
	if len(strings.trim_space(base)) == 0 {
		return
	}
	if npm == "@ai-sdk/anthropic" {
		hint_anthropic_endpoint(&scan.hints, "opencode", src, base, key, model, mtime)
		return
	}
	hint_compat_provider(&scan.hints, "opencode", src, base, key, model, mtime)
}

@(private)
foreign_scan_opencode :: proc(scan: ^Foreign_Scan) {
	if d := foreign_xdg_data(); len(d) > 0 {
		foreign_scan_opencode_auth(scan, foreign_join(d, "opencode", "auth.json"))
	}
	// v2 moved creds into a SQLite db. Flag it so doctor explains the gap.
	if d := foreign_xdg_data(); len(d) > 0 {
		db := foreign_join(d, "opencode", "opencode.db")
		if _, _, ok := foreign_read(db); ok {
			note_push(&scan.notes, "opencode", "opencode.db present; sqlite creds are not readable")
		}
	}
	cfg := ""
	if v, ok := os.lookup_env("OPENCODE_CONFIG", context.temp_allocator); ok && len(v) > 0 {
		cfg = v
	} else if d := foreign_xdg_config(); len(d) > 0 {
		names := [2]string{"opencode.json", "opencode.jsonc"}
		for name in names {
			p := foreign_join(d, "opencode", name)
			if _, _, ok := foreign_read(p); ok {
				cfg = p
				break
			}
		}
	}
	if len(cfg) == 0 {
		return
	}
	doc, mtime, ok := foreign_json(cfg)
	if !ok {
		return
	}
	src := foreign_disp(cfg)
	providers, _ := fj_obj(fj_get(doc, "provider"))
	// Inline keys on known providers are adoptable even without a model vote.
	if len(providers) > 0 {
		for pid, pv in providers {
			fp, known := foreign_provider(pid)
			if !known || len(fp.key_env) == 0 {
				continue
			}
			opts, _ := fj_obj(fj_get(pv, "options"))
			key := foreign_resolve_value(fj_str(opts["apiKey"]))
			if len(key) > 0 {
				hint_push(&scan.hints, "opencode", src, fp.key_env, key, true, 0, mtime)
			}
		}
	}
	sel := fj_str(fj_get(doc, "model"))
	prov, model := foreign_split_model(sel)
	if len(prov) == 0 || len(model) == 0 {
		return
	}
	foreign_opencode_provider_opts(scan, src, prov, model, providers, mtime)
}

@(private)
foreign_scan_pi :: proc(scan: ^Foreign_Scan) {
	home := foreign_home()
	if len(home) == 0 {
		return
	}
	dir := foreign_join(home, ".pi", "agent")
	tool := "pi"

	auth := foreign_join(dir, "auth.json")
	if doc, mtime, ok := foreign_json(auth); ok {
		src := foreign_disp(auth)
		obj, _ := fj_obj(doc)
		for pid, entry in obj {
			eobj, eok := fj_obj(entry)
			if !eok {
				continue
			}
			fp, known := foreign_provider(pid)
			switch fj_str(eobj["type"]) {
			case "api_key":
				if !known || len(fp.key_env) == 0 {
					continue
				}
				hint_push(&scan.hints, tool, src, fp.key_env,
					foreign_resolve_value(fj_str(eobj["key"])), true, 0, mtime)
			case "oauth":
				if pid == "opencode" || pid == "opencode-go" {
					hint_push(&scan.hints, tool, src, constants.ENV_OPENCODE_KEY,
						foreign_resolve_value(fj_str(eobj["access"])), true, 0, mtime)
				} else {
					note_push(&scan.notes, tool, fmt.tprintf("oauth for %s not importable", pid))
				}
			}
		}
	}

	settings := foreign_join(dir, "settings.json")
	sdoc, smtime, sok := foreign_json(settings)
	if !sok {
		return
	}
	ssrc := foreign_disp(settings)
	effort := fj_str(fj_get(sdoc, "defaultThinkingLevel"))
	if effort == "off" {
		effort = "none"
	}
	if len(effort) > 0 {
		hint_push(&scan.hints, tool, ssrc, constants.ENV_REASONING, effort, false, 1, smtime)
	}
	prov := fj_str(fj_get(sdoc, "defaultProvider"))
	model := fj_str(fj_get(sdoc, "defaultModel"))
	if len(prov) == 0 {
		return
	}
	if fp, known := foreign_provider(prov); known {
		hint_provider_model(&scan.hints, tool, ssrc, fp.id, model, fp.key_env, smtime)
		return
	}
	// Custom provider ids resolve through models.json.
	models_path := foreign_join(dir, "models.json")
	mdoc, mmtime, mok := foreign_json(models_path)
	if !mok {
		return
	}
	entry := fj_dig(mdoc, "providers", prov)
	eobj, eok := fj_obj(entry)
	if !eok {
		return
	}
	msrc := foreign_disp(models_path)
	base := foreign_resolve_value(fj_str(eobj["baseUrl"]))
	key := fj_str(eobj["apiKey"])
	api := fj_str(eobj["api"])
	if api == "anthropic-messages" {
		hint_anthropic_endpoint(&scan.hints, tool, msrc, base, key, model, mmtime)
		return
	}
	hint_compat_provider(&scan.hints, tool, msrc, base, key, model, mmtime)
}
