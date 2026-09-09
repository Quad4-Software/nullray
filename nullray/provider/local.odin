// SPDX-License-Identifier: 0BSD
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

// Short HTTP probe for local OpenAI-compat hosts (setup, readiness, auto-select).
probe_local_provider :: proc(id: string, timeout_sec := 2) -> bool {
	if !local_probe_enabled_from_env() {
		return false
	}
	p: Provider
	switch id {
	case "ollama":
		p = make_ollama()
		defer provider_destroy(&p)
		models, err := ollama_list_models_timeout(&p, timeout_sec)
		defer destroy_models(models)
		defer delete(err)
		return err == "" && len(models) > 0
	case "lmstudio":
		p = make_lmstudio()
		defer provider_destroy(&p)
		models, err := lmstudio_list_models_timeout(&p, timeout_sec)
		defer destroy_models(models)
		defer delete(err)
		return err == "" && len(models) > 0
	case "llamacpp":
		p = make_llamacpp()
		defer provider_destroy(&p)
		models, err := llamacpp_list_models_timeout(&p, timeout_sec)
		defer destroy_models(models)
		defer delete(err)
		return err == "" && len(models) > 0
	}
	return false
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
