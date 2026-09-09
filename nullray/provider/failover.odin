// SPDX-License-Identifier: 0BSD
/*
Auth classification and multi-provider chat failover.
*/

package provider

import "core:fmt"
import "core:os"
import "core:strings"
import "nullray:constants"

Auth_Kind :: enum {
	Ok,
	Dead_Key,
	Credits_Only,
	Payment,
	Other,
}

auth_kind_from_err :: proc(err: string) -> Auth_Kind {
	if len(err) == 0 {
		return .Ok
	}
	lower := strings.to_lower(err, context.temp_allocator)
	if strings.contains(lower, "user not found") ||
	   strings.contains(lower, "key revoked") ||
	   strings.contains(lower, "account missing") ||
	   strings.contains(lower, "invalid api key") ||
	   strings.contains(lower, "incorrect api key") {
		return .Dead_Key
	}
	if strings.contains(lower, "402") || strings.contains(lower, "payment required") || strings.contains(lower, "credits exhausted") {
		return .Payment
	}
	if strings.contains(lower, "401") || strings.contains(lower, "unauthorized") {
		return .Dead_Key
	}
	return .Other
}

auth_is_failover_worthy :: proc(err: string) -> bool {
	switch auth_kind_from_err(err) {
	case .Dead_Key, .Payment:
		return true
	case .Ok, .Credits_Only, .Other:
		return false
	}
	return false
}

provider_fallback_ids :: proc(allocator := context.temp_allocator) -> []string {
	v, ok := os.lookup_env(constants.ENV_PROVIDER_FALLBACKS, allocator)
	if !ok || len(strings.trim_space(v)) == 0 {
		return nil
	}
	parts := strings.split(v, ",", allocator)
	out := make([dynamic]string, allocator)
	for p in parts {
		id := strings.trim_space(strings.to_lower(p, allocator))
		if len(id) == 0 {
			continue
		}
		append(&out, id)
	}
	return out[:]
}

openrouter_credits_key :: proc(chat_key: string, allocator := context.temp_allocator) -> string {
	if v, ok := os.lookup_env(constants.ENV_OPENROUTER_CREDITS_KEY, allocator); ok && len(strings.trim_space(v)) > 0 {
		return strings.trim_space(v)
	}
	return chat_key
}

/*
Build a fresh provider instance for failover by id (keys from env).
Caller owns and must provider_destroy.
*/
make_provider_by_id :: proc(id: string) -> (Provider, bool) {
	switch strings.to_lower(strings.trim_space(id), context.temp_allocator) {
	case "ollama":
		return make_ollama(), true
	case "lmstudio", "lm-studio":
		return make_lmstudio(), true
	case "llamacpp", "llama.cpp", "llama-cpp", "llama":
		return make_llamacpp(), true
	case "openai":
		return make_openai(), true
	case "openai-compat", "compat":
		return make_openai_compat(), true
	case "openrouter":
		return make_openrouter(), true
	case "opencode":
		return make_opencode(), true
	case "opencode-go":
		return make_opencode_go(), true
	case "anthropic":
		return make_anthropic(), true
	case "gemini", "google":
		return make_gemini(), true
	case "groq":
		return make_groq(), true
	case "deepseek":
		return make_deepseek(), true
	case "mistral":
		return make_mistral(), true
	case "together":
		return make_together(), true
	case "fireworks":
		return make_fireworks(), true
	case "xai":
		return make_xai(), true
	case "azure":
		return make_azure(), true
	case "cerebras":
		return make_cerebras(), true
	case "cohere":
		return make_cohere(), true
	case "nvidia":
		return make_nvidia(), true
	case "dashscope":
		return make_dashscope(), true
	}
	return {}, false
}

provider_needs_key :: proc(p: ^Provider) -> bool {
	if p == nil {
		return true
	}
	switch p.id {
	case "ollama", "llamacpp":
		return false
	case "lmstudio", "openai-compat":
		return false
	}
	return true
}

provider_ready_for_chat :: proc(p: ^Provider) -> bool {
	if p == nil || p.chat == nil {
		return false
	}
	if provider_needs_key(p) && len(p.api_key) == 0 {
		return false
	}
	return len(p.base_url) > 0 || p.id == "ollama" || p.id == "llamacpp"
}

/*
Try a one-message chat to verify the provider can chat (not only list models).
*/
provider_probe_chat :: proc(p: ^Provider, allocator := context.allocator) -> (ok: bool, err: string) {
	if !provider_ready_for_chat(p) {
		return false, strings.clone("provider not ready", allocator)
	}
	msgs := []Message{
		{role = .User, content = "Reply with ok"},
	}
	req := Chat_Request{
		model = p.default_model,
		messages = msgs,
		stream = false,
		max_tokens = 8,
	}
	res := p.chat(p, req)
	defer destroy_chat_response(&res)
	if !res.ok {
		return false, strings.clone(res.err, allocator)
	}
	return true, ""
}

failover_note :: proc(from_id, to_id, why: string, allocator := context.allocator) -> string {
	return fmt.aprintf("fell back %s -> %s (%s)", from_id, to_id, why, allocator = allocator)
}
