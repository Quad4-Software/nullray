// SPDX-License-Identifier: 0BSD
/*
Built-in providers: local hosts, OpenAI-compat clouds, OpenRouter, OpenCode.
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
		stream = openai_chat_stream,
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
		stream = openai_chat_stream,
		list_models = lmstudio_list_models,
	}
}

make_llamacpp :: proc(base_url := "", api_key := "", model := "") -> Provider {
	base := base_url
	if len(base) == 0 {
		if host, ok := os.lookup_env(constants.ENV_LLAMACPP_HOST, context.temp_allocator); ok {
			base = normalize_openai_base(host)
		} else {
			base = constants.DEFAULT_LLAMACPP_BASE
		}
	} else {
		base = normalize_openai_base(base)
	}
	key := api_key
	if len(key) == 0 {
		if v, ok := os.lookup_env(constants.ENV_LLAMACPP_KEY, context.temp_allocator); ok {
			key = v
		}
	}
	m := model
	if len(m) == 0 {
		m = constants.DEFAULT_MODEL_LLAMACPP
	}
	return Provider{
		id = "llamacpp",
		name = "llama.cpp",
		base_url = strings.clone(base),
		api_key = strings.clone(key),
		default_model = strings.clone(m),
		chat = openai_chat,
		stream = openai_chat_stream,
		list_models = llamacpp_list_models,
	}
}

make_openrouter :: proc(base_url := "", api_key := "", model := "") -> Provider {
	base := base_url
	if len(base) == 0 {
		base = constants.DEFAULT_OPENROUTER_BASE
	}
	key := api_key
	if len(key) == 0 {
		key = lookup_api_key_env(constants.ENV_OPENROUTER_KEY, constants.ENV_API_KEY)
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
		stream = openai_chat_stream,
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
		key = lookup_api_key_env(constants.ENV_OPENCODE_KEY, constants.ENV_API_KEY)
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
		stream = openai_chat_stream,
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
		key = lookup_api_key_env(constants.ENV_OPENCODE_KEY, constants.ENV_API_KEY)
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
		stream = openai_chat_stream,
		list_models = openai_list_models,
	}
}

make_openai :: proc(base_url := "", api_key := "", model := "") -> Provider {
	base := base_url
	if len(base) == 0 {
		if host, ok := os.lookup_env(constants.ENV_OPENAI_BASE, context.temp_allocator); ok {
			base = normalize_openai_base(host)
		} else {
			base = constants.DEFAULT_OPENAI_BASE
		}
	} else {
		base = normalize_openai_base(base)
	}
	key := api_key
	if len(key) == 0 {
		key = lookup_api_key_env(constants.ENV_OPENAI_KEY, constants.ENV_API_KEY)
	}
	m := model
	if len(m) == 0 {
		m = constants.DEFAULT_MODEL_OPENAI
	}
	return Provider{
		id = "openai",
		name = "OpenAI",
		base_url = strings.clone(base),
		api_key = strings.clone(key),
		default_model = strings.clone(m),
		chat = openai_chat,
		stream = openai_chat_stream,
		list_models = openai_list_models,
	}
}

// Any OpenAI Chat Completions compatible endpoint (vLLM, LiteLLM, Azure proxy, Groq, …).
make_openai_compat :: proc(base_url := "", api_key := "", model := "") -> Provider {
	base := base_url
	if len(base) == 0 {
		if host, ok := os.lookup_env(constants.ENV_OPENAI_BASE, context.temp_allocator); ok {
			base = normalize_openai_base(host)
		} else if host2, ok2 := os.lookup_env(constants.ENV_BASE_URL, context.temp_allocator); ok2 {
			base = normalize_openai_base(host2)
		}
	} else {
		base = normalize_openai_base(base)
	}
	key := api_key
	if len(key) == 0 {
		key = lookup_api_key_env(constants.ENV_OPENAI_KEY, constants.ENV_API_KEY)
	}
	m := model
	if len(m) == 0 {
		if mv, mok := os.lookup_env(constants.ENV_MODEL, context.temp_allocator); mok && len(mv) > 0 {
			m = mv
		} else {
			m = constants.DEFAULT_MODEL_OPENAI_COMPAT
		}
	}
	return Provider{
		id = "openai-compat",
		name = "OpenAI Compat",
		base_url = strings.clone(base),
		api_key = strings.clone(key),
		default_model = strings.clone(m),
		chat = openai_chat,
		stream = openai_chat_stream,
		list_models = openai_list_models,
	}
}

make_azure :: proc(base_url := "", api_key := "", model := "") -> Provider {
	base := base_url
	if len(base) == 0 {
		if host, ok := os.lookup_env(constants.ENV_AZURE_BASE, context.temp_allocator); ok {
			base = normalize_openai_base(host)
		}
	} else {
		base = normalize_openai_base(base)
	}
	key := api_key
	if len(key) == 0 {
		key = lookup_api_key_env(constants.ENV_AZURE_KEY, constants.ENV_OPENAI_KEY, constants.ENV_API_KEY)
	}
	m := model
	if len(m) == 0 {
		m = constants.DEFAULT_MODEL_AZURE
	}
	return Provider{
		id = "azure",
		name = "Azure OpenAI",
		base_url = strings.clone(base),
		api_key = strings.clone(key),
		default_model = strings.clone(m),
		chat = openai_chat,
		stream = openai_chat_stream,
		list_models = openai_list_models,
	}
}

provider_destroy :: proc(p: ^Provider) {
	delete(p.base_url)
	delete(p.api_key)
	delete(p.default_model)
	p^ = {}
}
