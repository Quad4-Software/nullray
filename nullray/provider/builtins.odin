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
		if v, ok := os.lookup_env(constants.ENV_OPENAI_KEY, context.temp_allocator); ok {
			key = v
		} else if v2, ok2 := os.lookup_env(constants.ENV_API_KEY, context.temp_allocator); ok2 {
			key = v2
		}
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
		if v, ok := os.lookup_env(constants.ENV_OPENAI_KEY, context.temp_allocator); ok {
			key = v
		} else if v2, ok2 := os.lookup_env(constants.ENV_API_KEY, context.temp_allocator); ok2 {
			key = v2
		}
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
		list_models = openai_list_models,
	}
}

@(private)
make_compat_named :: proc(
	id, name, default_base, default_model, key_env: string,
	base_url := "",
	api_key := "",
	model := "",
	alt_key_env := "",
) -> Provider {
	base := base_url
	if len(base) == 0 {
		base = default_base
	} else {
		base = normalize_openai_base(base)
	}
	key := api_key
	if len(key) == 0 {
		if v, ok := os.lookup_env(key_env, context.temp_allocator); ok {
			key = v
		} else if len(alt_key_env) > 0 {
			if v2, ok2 := os.lookup_env(alt_key_env, context.temp_allocator); ok2 {
				key = v2
			}
		}
		if len(key) == 0 {
			if v3, ok3 := os.lookup_env(constants.ENV_API_KEY, context.temp_allocator); ok3 {
				key = v3
			}
		}
	}
	m := model
	if len(m) == 0 {
		m = default_model
	}
	return Provider{
		id = id,
		name = name,
		base_url = strings.clone(base),
		api_key = strings.clone(key),
		default_model = strings.clone(m),
		chat = openai_chat,
		list_models = openai_list_models,
	}
}

make_anthropic :: proc(base_url := "", api_key := "", model := "") -> Provider {
	return make_compat_named(
		"anthropic",
		"Anthropic",
		constants.DEFAULT_ANTHROPIC_BASE,
		constants.DEFAULT_MODEL_ANTHROPIC,
		constants.ENV_ANTHROPIC_KEY,
		base_url,
		api_key,
		model,
	)
}

make_gemini :: proc(base_url := "", api_key := "", model := "") -> Provider {
	return make_compat_named(
		"gemini",
		"Gemini",
		constants.DEFAULT_GEMINI_BASE,
		constants.DEFAULT_MODEL_GEMINI,
		constants.ENV_GEMINI_KEY,
		base_url,
		api_key,
		model,
		constants.ENV_GOOGLE_KEY,
	)
}

make_groq :: proc(base_url := "", api_key := "", model := "") -> Provider {
	return make_compat_named(
		"groq",
		"Groq",
		constants.DEFAULT_GROQ_BASE,
		constants.DEFAULT_MODEL_GROQ,
		constants.ENV_GROQ_KEY,
		base_url,
		api_key,
		model,
	)
}

make_deepseek :: proc(base_url := "", api_key := "", model := "") -> Provider {
	return make_compat_named(
		"deepseek",
		"DeepSeek",
		constants.DEFAULT_DEEPSEEK_BASE,
		constants.DEFAULT_MODEL_DEEPSEEK,
		constants.ENV_DEEPSEEK_KEY,
		base_url,
		api_key,
		model,
	)
}

make_mistral :: proc(base_url := "", api_key := "", model := "") -> Provider {
	return make_compat_named(
		"mistral",
		"Mistral",
		constants.DEFAULT_MISTRAL_BASE,
		constants.DEFAULT_MODEL_MISTRAL,
		constants.ENV_MISTRAL_KEY,
		base_url,
		api_key,
		model,
	)
}

make_together :: proc(base_url := "", api_key := "", model := "") -> Provider {
	return make_compat_named(
		"together",
		"Together",
		constants.DEFAULT_TOGETHER_BASE,
		constants.DEFAULT_MODEL_TOGETHER,
		constants.ENV_TOGETHER_KEY,
		base_url,
		api_key,
		model,
	)
}

make_fireworks :: proc(base_url := "", api_key := "", model := "") -> Provider {
	return make_compat_named(
		"fireworks",
		"Fireworks",
		constants.DEFAULT_FIREWORKS_BASE,
		constants.DEFAULT_MODEL_FIREWORKS,
		constants.ENV_FIREWORKS_KEY,
		base_url,
		api_key,
		model,
	)
}

make_xai :: proc(base_url := "", api_key := "", model := "") -> Provider {
	return make_compat_named(
		"xai",
		"xAI",
		constants.DEFAULT_XAI_BASE,
		constants.DEFAULT_MODEL_XAI,
		constants.ENV_XAI_KEY,
		base_url,
		api_key,
		model,
	)
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
		if v, ok := os.lookup_env(constants.ENV_AZURE_KEY, context.temp_allocator); ok {
			key = v
		} else if v2, ok2 := os.lookup_env(constants.ENV_OPENAI_KEY, context.temp_allocator); ok2 {
			key = v2
		}
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
		list_models = openai_list_models,
	}
}

provider_destroy :: proc(p: ^Provider) {
	delete(p.base_url)
	delete(p.api_key)
	delete(p.default_model)
	p^ = {}
}
