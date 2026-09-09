// SPDX-License-Identifier: 0BSD
/*
Provider readiness labels for TUI status and /providers.
*/

package provider

import "core:strings"

// Builtin registry ids in registration order. Used for slash and shell completions.
PROVIDER_IDS :: []string{
	"ollama",
	"lmstudio",
	"llamacpp",
	"openai",
	"openai-compat",
	"openrouter",
	"opencode",
	"opencode-go",
	"anthropic",
	"gemini",
	"groq",
	"deepseek",
	"mistral",
	"together",
	"fireworks",
	"xai",
	"azure",
	"cerebras",
	"cohere",
	"nvidia",
	"dashscope",
}

// Local OpenAI-compat hosts (no cloud API key required by default).
provider_is_local :: proc(id: string) -> bool {
	switch id {
	case "ollama", "lmstudio", "llamacpp":
		return true
	}
	return false
}

/*
Readiness for status lines. Labels: live, down, configured, no key, no base, none.
probe enables a short local HTTP check for ollama, lmstudio, and llamacpp.
*/
provider_readiness_label :: proc(p: ^Provider, probe := true) -> string {
	if p == nil {
		return "none"
	}
	if provider_is_local(p.id) {
		if !probe || !local_probe_enabled_from_env() {
			return "local"
		}
		if probe_local_provider(p.id, 2) {
			return "live"
		}
		return "down"
	}
	if (p.id == "azure" || p.id == "openai-compat") && len(strings.trim_space(p.base_url)) == 0 {
		return "no base"
	}
	if p.id == "openai-compat" {
		return "configured"
	}
	if len(strings.trim_space(p.api_key)) == 0 {
		return "no key"
	}
	return "configured"
}

provider_is_ready :: proc(p: ^Provider, probe := true) -> bool {
	label := provider_readiness_label(p, probe)
	return label == "configured" || label == "live"
}
