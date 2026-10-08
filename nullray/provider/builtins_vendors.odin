// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Named OpenAI-compat cloud providers kept in-tree.
Local servers (ollama, lmstudio, llamacpp) and gateway aliases
(openai-compat, openrouter, opencode) live in builtins.odin.
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
