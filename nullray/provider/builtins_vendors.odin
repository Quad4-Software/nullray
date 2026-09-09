// SPDX-License-Identifier: 0BSD
/*
Named OpenAI-compat cloud providers (Anthropic, Gemini, Groq, …).
*/

package provider

import "core:strings"
import "nullray:constants"

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
		key = lookup_api_key_env(key_env, alt_key_env, constants.ENV_API_KEY)
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
		stream = openai_chat_stream,
		list_models = openai_list_models,
		embed = openai_embed,
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

make_cerebras :: proc(base_url := "", api_key := "", model := "") -> Provider {
	return make_compat_named(
		"cerebras",
		"Cerebras",
		constants.DEFAULT_CEREBRAS_BASE,
		constants.DEFAULT_MODEL_CEREBRAS,
		constants.ENV_CEREBRAS_KEY,
		base_url,
		api_key,
		model,
	)
}

make_cohere :: proc(base_url := "", api_key := "", model := "") -> Provider {
	return make_compat_named(
		"cohere",
		"Cohere",
		constants.DEFAULT_COHERE_BASE,
		constants.DEFAULT_MODEL_COHERE,
		constants.ENV_COHERE_KEY,
		base_url,
		api_key,
		model,
		constants.ENV_COHERE_KEY_ALT,
	)
}

make_nvidia :: proc(base_url := "", api_key := "", model := "") -> Provider {
	return make_compat_named(
		"nvidia",
		"NVIDIA",
		constants.DEFAULT_NVIDIA_BASE,
		constants.DEFAULT_MODEL_NVIDIA,
		constants.ENV_NVIDIA_KEY,
		base_url,
		api_key,
		model,
	)
}

make_dashscope :: proc(base_url := "", api_key := "", model := "") -> Provider {
	return make_compat_named(
		"dashscope",
		"DashScope",
		constants.DEFAULT_DASHSCOPE_BASE,
		constants.DEFAULT_MODEL_DASHSCOPE,
		constants.ENV_DASHSCOPE_KEY,
		base_url,
		api_key,
		model,
	)
}
