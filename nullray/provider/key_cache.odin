// SPDX-License-Identifier: 0BSD
/*
Snapshot provider API keys from the environment before privacy scrub.
Failover remakes providers after scrub and must not fall back to a shared
NULLRAY_API_KEY when the vendor-specific key was only present pre-scrub.
*/

package provider

import "core:os"
import "core:strings"
import "core:sync"
import "nullray:constants"

@(private)
g_key_cache_mu: sync.Mutex
@(private)
g_key_cache: map[string]string

/*
Capture known provider key env vars. Call once before sandbox.apply privacy scrub.
*/
cache_api_keys_from_env :: proc() {
	sync.mutex_lock(&g_key_cache_mu)
	defer sync.mutex_unlock(&g_key_cache_mu)
	if g_key_cache == nil {
		g_key_cache = make(map[string]string)
	} else {
		for k, v in g_key_cache {
			delete(k)
			delete(v)
		}
		clear(&g_key_cache)
	}
	envs := []string{
		constants.ENV_API_KEY,
		constants.ENV_OPENROUTER_KEY,
		constants.ENV_OPENCODE_KEY,
		constants.ENV_LMSTUDIO_KEY,
		constants.ENV_LLAMACPP_KEY,
		constants.ENV_OPENAI_KEY,
		constants.ENV_ANTHROPIC_KEY,
		constants.ENV_GEMINI_KEY,
		constants.ENV_GROQ_KEY,
		constants.ENV_DEEPSEEK_KEY,
		constants.ENV_MISTRAL_KEY,
		constants.ENV_TOGETHER_KEY,
		constants.ENV_FIREWORKS_KEY,
		constants.ENV_XAI_KEY,
		constants.ENV_AZURE_KEY,
		constants.ENV_CEREBRAS_KEY,
		constants.ENV_COHERE_KEY,
		constants.ENV_COHERE_KEY_ALT,
		constants.ENV_NVIDIA_KEY,
		constants.ENV_DASHSCOPE_KEY,
		constants.ENV_OPENROUTER_CREDITS_KEY,
	}
	for e in envs {
		if v, ok := os.lookup_env(e, context.temp_allocator); ok && len(strings.trim_space(v)) > 0 {
			g_key_cache[strings.clone(e)] = strings.clone(strings.trim_space(v))
		}
	}
}

cached_api_key :: proc(env_name: string) -> string {
	sync.mutex_lock(&g_key_cache_mu)
	defer sync.mutex_unlock(&g_key_cache_mu)
	if g_key_cache == nil {
		return ""
	}
	if v, ok := g_key_cache[env_name]; ok {
		return v
	}
	return ""
}

lookup_api_key_env :: proc(primary: string, alts: ..string) -> string {
	if v, ok := os.lookup_env(primary, context.temp_allocator); ok && len(strings.trim_space(v)) > 0 {
		return strings.trim_space(v)
	}
	if c := cached_api_key(primary); len(c) > 0 {
		return c
	}
	for a in alts {
		if len(a) == 0 {
			continue
		}
		if v, ok := os.lookup_env(a, context.temp_allocator); ok && len(strings.trim_space(v)) > 0 {
			return strings.trim_space(v)
		}
		if c := cached_api_key(a); len(c) > 0 {
			return c
		}
	}
	return ""
}
