// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Ollama, LM Studio, and llama.cpp helpers beyond plain OpenAI-compat.
*/

package provider

import "core:encoding/json"
import "core:os"
import "core:strings"
import "nullray:constants"
import "nullray:http"

LOCAL_PROBE_IDS :: []string{"ollama", "lmstudio", "llamacpp"}

// Common llama-server listen ports. 8080 is the historic default, 8081 is a
// frequent alternate, 9931 is the newer upstream default.
LLAMACPP_BASES :: []string{
	constants.DEFAULT_LLAMACPP_BASE,
	"http://127.0.0.1:8081/v1",
	"http://127.0.0.1:9931/v1",
}

local_probe_enabled_from_env :: proc() -> bool {
	if v, ok := os.lookup_env(constants.ENV_LOCAL_PROBE, context.temp_allocator); ok {
		switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
		case "0", "false", "off", "no", "disable", "disabled":
			return false
		}
	}
	return true
}

ollama_list_models :: proc(p: ^Provider, allocator := context.allocator) -> (models: []Model_Info, err: string) {
	return ollama_list_models_timeout(p, 30, allocator)
}

ollama_list_models_timeout :: proc(
	p: ^Provider,
	timeout_sec: int,
	allocator := context.allocator,
) -> (
	models: []Model_Info,
	err: string,
) {
	models, err = openai_list_models_timeout(p, timeout_sec, allocator)
	if err == "" && len(models) > 0 {
		return models, ""
	}
	if len(models) > 0 {
		destroy_models(models)
		models = nil
	}
	saved_err := err

	root := openai_compat_root(p.base_url)
	url := http.join_url(root, "/api/tags")
	res := http.get(url, nil, timeout_sec, context.temp_allocator)
	if !res.ok {
		if len(saved_err) > 0 {
			return nil, saved_err
		}
		return nil, strings.clone(res.err, allocator)
	}
	models, err = parse_ollama_tags_body(res.body, allocator)
	if len(err) == 0 {
		delete(saved_err)
		return models, ""
	}
	if len(saved_err) > 0 {
		delete(err)
		return nil, saved_err
	}
	return nil, err
}

lmstudio_list_models :: proc(p: ^Provider, allocator := context.allocator) -> (models: []Model_Info, err: string) {
	return openai_list_models(p, allocator)
}

lmstudio_list_models_timeout :: proc(
	p: ^Provider,
	timeout_sec: int,
	allocator := context.allocator,
) -> (
	models: []Model_Info,
	err: string,
) {
	return openai_list_models_timeout(p, timeout_sec, allocator)
}

llamacpp_list_models :: proc(p: ^Provider, allocator := context.allocator) -> (models: []Model_Info, err: string) {
	return openai_list_models(p, allocator)
}

llamacpp_list_models_timeout :: proc(
	p: ^Provider,
	timeout_sec: int,
	allocator := context.allocator,
) -> (
	models: []Model_Info,
	err: string,
) {
	return openai_list_models_timeout(p, timeout_sec, allocator)
}

// True when a base was pinned via LLAMA_CPP_HOST or NULLRAY_BASE_URL.
llamacpp_base_pinned :: proc() -> bool {
	if !local_probe_enabled_from_env() {
		return true
	}
	host, has_host := os.lookup_env(constants.ENV_LLAMACPP_HOST, context.temp_allocator)
	base_env, has_base := os.lookup_env(constants.ENV_BASE_URL, context.temp_allocator)
	return (has_host && len(strings.trim_space(host)) > 0) ||
		(has_base && len(strings.trim_space(base_env)) > 0)
}

/*
llama.cpp probe candidates: an explicit LLAMA_CPP_HOST wins alone (user pinned
a host), otherwise the classic 8080 and newer 9931 defaults are tried.
*/
llamacpp_probe_bases :: proc(allocator := context.temp_allocator) -> []string {
	if host, ok := os.lookup_env(constants.ENV_LLAMACPP_HOST, context.temp_allocator);
	   ok && len(strings.trim_space(host)) > 0 {
		out := make([]string, 1, allocator)
		out[0] = normalize_openai_base(host, allocator)
		return out
	}
	out := make([]string, len(LLAMACPP_BASES), allocator)
	for b, i in LLAMACPP_BASES {
		out[i] = strings.clone(b, allocator)
	}
	return out
}

/*
Returns the live base URL for a local provider id, or "" when nothing answers.
For llamacpp the base may differ from the configured default when the server
listens on an alternate known port.
*/
probe_local_base :: proc(id: string, timeout_sec := 2, allocator := context.temp_allocator) -> string {
	if !local_probe_enabled_from_env() {
		return ""
	}
	switch id {
	case "ollama":
		p := make_ollama()
		defer provider_destroy(&p)
		models, err := ollama_list_models_timeout(&p, timeout_sec)
		defer destroy_models(models)
		defer delete(err)
		if err == "" && len(models) > 0 {
			return strings.clone(p.base_url, allocator)
		}
	case "lmstudio":
		p := make_lmstudio()
		defer provider_destroy(&p)
		models, err := lmstudio_list_models_timeout(&p, timeout_sec)
		defer destroy_models(models)
		defer delete(err)
		if err == "" && len(models) > 0 {
			return strings.clone(p.base_url, allocator)
		}
	case "llamacpp":
		for base in llamacpp_probe_bases() {
			p := make_llamacpp(base)
			models, err := llamacpp_list_models_timeout(&p, timeout_sec)
			live := err == "" && len(models) > 0
			// A 401/403 still proves a server is there, adopt the base so chat
			// surfaces a real auth error instead of a misleading refused.
			blocked := strings.has_prefix(err, "HTTP 401") ||
				strings.has_prefix(err, "HTTP 403")
			provider_destroy(&p)
			destroy_models(models)
			delete(err)
			if live || blocked {
				return strings.clone(base, allocator)
			}
		}
	}
	return ""
}

// Pick a useful default model id from a live llama.cpp /v1/models list.
// Prefers non-embed models; falls back to the first entry.
llamacpp_pick_default_model :: proc(models: []Model_Info) -> string {
	if len(models) == 0 {
		return ""
	}
	for m in models {
		id_l := strings.to_lower(m.id, context.temp_allocator)
		if strings.contains(id_l, "embed") || strings.contains(id_l, "embedding") {
			continue
		}
		return m.id
	}
	return models[0].id
}

// After a live base is known, fill an empty or generic default_model from
// /v1/models so the title bar and first chat use the loaded GGUF name.
llamacpp_adopt_live_model :: proc(p: ^Provider, timeout_sec := 2) {
	if p == nil || p.id != "llamacpp" {
		return
	}
	// Respect an explicit user model.
	if model_env_set() {
		return
	}
	generic := p.default_model == "local" || len(strings.trim_space(p.default_model)) == 0
	if !generic {
		return
	}
	models, err := llamacpp_list_models_timeout(p, timeout_sec)
	defer destroy_models(models)
	defer delete(err)
	if err != "" || len(models) == 0 {
		return
	}
	pick := llamacpp_pick_default_model(models)
	if len(pick) == 0 {
		return
	}
	delete(p.default_model)
	p.default_model = strings.clone(pick)
}

// Short HTTP probe for local OpenAI-compat hosts (setup, readiness, auto-select).
probe_local_provider :: proc(id: string, timeout_sec := 2) -> bool {
	return len(probe_local_base(id, timeout_sec)) > 0
}

openai_compat_root :: proc(base_url: string, allocator := context.temp_allocator) -> string {
	b := strings.trim_right(base_url, "/")
	if strings.has_suffix(b, "/v1") {
		return strings.clone(b[:len(b) - 3], allocator)
	}
	return strings.clone(b, allocator)
}

normalize_openai_base :: proc(base_url: string, allocator := context.temp_allocator) -> string {
	b := strings.trim_right(base_url, "/")
	if len(b) == 0 {
		return strings.clone(b, allocator)
	}
	if strings.has_suffix(b, "/v1") {
		return strings.clone(b, allocator)
	}
	return strings.concatenate({b, "/v1"}, allocator)
}

parse_ollama_tags_body :: proc(body: string, allocator := context.allocator) -> (models: []Model_Info, err: string) {
	doc, parse_err := json.parse_string(body, .JSON, allocator = context.temp_allocator)
	if parse_err != .None {
		return nil, strings.clone("bad ollama tags JSON", allocator)
	}
	obj, obj_ok := doc.(json.Object)
	if !obj_ok {
		return nil, strings.clone("unexpected ollama tags root", allocator)
	}
	arr_v, has := obj["models"]
	if !has {
		return nil, strings.clone("no ollama models field", allocator)
	}
	arr, aok := arr_v.(json.Array)
	if !aok {
		return nil, strings.clone("ollama models not array", allocator)
	}
	out := make([dynamic]Model_Info, allocator)
	for item in arr {
		mobj, mok := item.(json.Object)
		if !mok {
			continue
		}
		id := ""
		if v, ok := mobj["name"]; ok {
			if s, sok := v.(json.String); sok {
				id = string(s)
			}
		}
		if len(id) == 0 {
			if v, ok := mobj["model"]; ok {
				if s, sok := v.(json.String); sok {
					id = string(s)
				}
			}
		}
		if len(id) == 0 {
			continue
		}
		append(&out, Model_Info{id = strings.clone(id, allocator), name = strings.clone(id, allocator)})
	}
	return out[:], ""
}

destroy_models :: proc(models: []Model_Info) {
	for m in models {
		delete(m.id)
		delete(m.name)
		delete(m.reasoning_default)
		for e in m.reasoning_efforts {
			delete(e)
		}
		delete(m.reasoning_efforts)
	}
	delete(models)
}
