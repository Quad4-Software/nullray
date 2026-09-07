/*
Built-in providers: Ollama, LM Studio, OpenRouter, OpenCode.
*/

package provider

import "core:os"
import "core:strings"
import "nullray:constants"

make_ollama :: proc(base_url := "", api_key := "", model := "") -> Provider {
	base := base_url
	if len(base) == 0 {
		if host, ok := os.lookup_env(constants.ENV_OLLAMA_HOST, context.temp_allocator); ok {
			base = normalize_openai_base(host)
		} else {
			base = constants.DEFAULT_OLLAMA_BASE
		}
	} else {
		base = normalize_openai_base(base)
	}
	m := model
	if len(m) == 0 {
		m = constants.DEFAULT_MODEL_OLLAMA
	}
	return Provider{
		id = "ollama",
		name = "Ollama",
		base_url = strings.clone(base),
		api_key = strings.clone(api_key),
		default_model = strings.clone(m),
		chat = openai_chat,
		list_models = ollama_list_models,
	}
}

make_lmstudio :: proc(base_url := "", api_key := "", model := "") -> Provider {
	base := base_url
	if len(base) == 0 {
		if host, ok := os.lookup_env(constants.ENV_LMSTUDIO_HOST, context.temp_allocator); ok {
			base = normalize_openai_base(host)
		} else {
			base = constants.DEFAULT_LMSTUDIO_BASE
		}
	} else {
		base = normalize_openai_base(base)
	}
	key := api_key
	if len(key) == 0 {
		if v, ok := os.lookup_env(constants.ENV_LMSTUDIO_KEY, context.temp_allocator); ok {
			key = v
		} else {
			key = "lm-studio"
		}
	}
	m := model
	if len(m) == 0 {
		m = constants.DEFAULT_MODEL_LMSTUDIO
	}
	return Provider{
		id = "lmstudio",
		name = "LM Studio",
		base_url = strings.clone(base),
		api_key = strings.clone(key),
		default_model = strings.clone(m),
		chat = openai_chat,
		list_models = lmstudio_list_models,
	}
}

make_openrouter :: proc(base_url := "", api_key := "", model := "") -> Provider {
	base := base_url
	if len(base) == 0 {
		base = constants.DEFAULT_OPENROUTER_BASE
	}
	key := api_key
	if len(key) == 0 {
		if v, ok := os.lookup_env(constants.ENV_OPENROUTER_KEY, context.temp_allocator); ok {
			key = v
		} else if v2, ok2 := os.lookup_env(constants.ENV_API_KEY, context.temp_allocator); ok2 {
			key = v2
		}
	}
	m := model
	if len(m) == 0 {
		m = constants.DEFAULT_MODEL_OPENROUTER
	}
	return Provider{
		id = "openrouter",
		name = "OpenRouter",
		base_url = strings.clone(base),
		api_key = strings.clone(key),
		default_model = strings.clone(m),
		chat = openai_chat,
		list_models = openai_list_models,
	}
}

make_opencode_go :: proc(base_url := "", api_key := "", model := "") -> Provider {
	base := base_url
	if len(base) == 0 {
		base = constants.DEFAULT_OPENCODE_GO_BASE
	}
	key := api_key
	if len(key) == 0 {
		if v, ok := os.lookup_env(constants.ENV_OPENCODE_KEY, context.temp_allocator); ok {
			key = v
		} else if v2, ok2 := os.lookup_env(constants.ENV_API_KEY, context.temp_allocator); ok2 {
			key = v2
		}
	}
	m := model
	if len(m) == 0 {
		m = constants.DEFAULT_MODEL_OPENCODE_GO
	}
	return Provider{
		id = "opencode-go",
		name = "OpenCode Go",
		base_url = strings.clone(base),
		api_key = strings.clone(key),
		default_model = strings.clone(m),
		chat = openai_chat,
		list_models = openai_list_models,
	}
}

make_opencode :: proc(base_url := "", api_key := "", model := "") -> Provider {
	base := base_url
	if len(base) == 0 {
		base = constants.DEFAULT_OPENCODE_BASE
	}
	key := api_key
	if len(key) == 0 {
		if v, ok := os.lookup_env(constants.ENV_OPENCODE_KEY, context.temp_allocator); ok {
			key = v
		} else if v2, ok2 := os.lookup_env(constants.ENV_API_KEY, context.temp_allocator); ok2 {
			key = v2
		}
	}
	m := model
	if len(m) == 0 {
		m = constants.DEFAULT_MODEL_OPENCODE
	}
	return Provider{
		id = "opencode",
		name = "OpenCode",
		base_url = strings.clone(base),
		api_key = strings.clone(key),
		default_model = strings.clone(m),
		chat = openai_chat,
		list_models = openai_list_models,
	}
}

provider_destroy :: proc(p: ^Provider) {
	delete(p.base_url)
	delete(p.api_key)
	delete(p.default_model)
	p^ = {}
}
