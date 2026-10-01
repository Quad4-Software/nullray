// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Adopt credentials and model settings from other AI CLIs already installed on
the machine (Claude Code, OpenCode, pi, Codex, Gemini CLI, Qwen Code, Crush,
goose, aider, aichat, llm). Each scanner reads that tool's user config files
and emits env hints. foreign_adopt fills only unset env vars, so explicit
env, ~/.config/nullray/env, and CLI flags always win. Helper commands
(apiKeyHelper, !cmd, {file:}) are never executed. NULLRAY_ADOPT=0 disables.
*/

package config

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import "nullray:constants"

Foreign_Hint :: struct {
	tool:        string, // "claude-code"
	source:      string, // display path like ~/.claude/settings.json
	env:         string, // env var to fill
	value:       string, // candidate value (never printed)
	secret:      bool,
	prio:        int,    // 0 keys, 1 plain envs, 2 provider votes, 3 provider-bound
	require_env: string, // must be non-empty before applying
	require_val: string, // when set, require_env must equal this
	mtime:       i64,    // source file mtime, orders provider votes
}

Foreign_Scan :: struct {
	hints: [dynamic]Foreign_Hint,
	notes: [dynamic]string, // informational, e.g. oauth creds that cannot import
}

@(private)
Foreign_Provider :: struct {
	id:      string,   // nullray provider id
	key_env: string,   // env holding its key
	local:   bool,     // works without a key, so votes need no credential
	aliases: []string, // lowercase ids used by foreign tools
}

@(private)
FOREIGN_PROVIDERS := []Foreign_Provider{
	{id = "anthropic", key_env = constants.ENV_ANTHROPIC_KEY, aliases = {"anthropic", "claude"}},
	{id = "openai", key_env = constants.ENV_OPENAI_KEY, aliases = {"openai"}},
	{id = "gemini", key_env = constants.ENV_GEMINI_KEY, aliases = {"google", "gemini"}},
	{id = "openrouter", key_env = constants.ENV_OPENROUTER_KEY, aliases = {"openrouter"}},
	{id = "opencode", key_env = constants.ENV_OPENCODE_KEY, aliases = {"opencode"}},
	{id = "opencode-go", key_env = constants.ENV_OPENCODE_KEY, aliases = {"opencode-go"}},
	{id = "groq", key_env = constants.ENV_GROQ_KEY, aliases = {"groq"}},
	{id = "deepseek", key_env = constants.ENV_DEEPSEEK_KEY, aliases = {"deepseek"}},
	{id = "mistral", key_env = constants.ENV_MISTRAL_KEY, aliases = {"mistral"}},
	{id = "xai", key_env = constants.ENV_XAI_KEY, aliases = {"xai", "grok"}},
	{id = "together", key_env = constants.ENV_TOGETHER_KEY, aliases = {"together", "togetherai", "together-ai"}},
	{id = "fireworks", key_env = constants.ENV_FIREWORKS_KEY, aliases = {"fireworks", "fireworks-ai"}},
	{id = "cerebras", key_env = constants.ENV_CEREBRAS_KEY, aliases = {"cerebras"}},
	{id = "cohere", key_env = constants.ENV_COHERE_KEY, aliases = {"cohere", "co"}},
	{id = "nvidia", key_env = constants.ENV_NVIDIA_KEY, aliases = {"nvidia", "nvidia-nim", "nim"}},
	{id = "dashscope", key_env = constants.ENV_DASHSCOPE_KEY, aliases = {"dashscope", "qwen", "alibaba", "modelstudio"}},
	{id = "azure", key_env = constants.ENV_AZURE_KEY, aliases = {"azure", "azure-openai", "azure_openai", "azure-openai-responses"}},
	{id = "ollama", local = true, aliases = {"ollama", "ollama_chat"}},
	{id = "lmstudio", key_env = constants.ENV_LMSTUDIO_KEY, local = true, aliases = {"lmstudio", "lm-studio"}},
	{id = "llamacpp", local = true, aliases = {"llamacpp", "llama.cpp", "llama-cpp"}},
	{id = "openai-compat", key_env = constants.ENV_OPENAI_KEY, aliases = {"openai-compat", "openai-compatible"}},
}

// Env names a generic env block or secrets file may adopt. Keys map to the
// vendor env var nullray providers already read. Bases and hosts ride the same
// per-vendor vars the builtins honor.
@(private)
FOREIGN_ADOPT_ENVS := []string{
	constants.ENV_ANTHROPIC_KEY,
	constants.ENV_OPENAI_KEY,
	constants.ENV_GEMINI_KEY,
	constants.ENV_GOOGLE_KEY,
	constants.ENV_OPENROUTER_KEY,
	constants.ENV_OPENCODE_KEY,
	constants.ENV_GROQ_KEY,
	constants.ENV_DEEPSEEK_KEY,
	constants.ENV_MISTRAL_KEY,
	constants.ENV_TOGETHER_KEY,
	constants.ENV_FIREWORKS_KEY,
	constants.ENV_XAI_KEY,
	constants.ENV_AZURE_KEY,
	constants.ENV_CEREBRAS_KEY,
	constants.ENV_COHERE_KEY,
	constants.ENV_NVIDIA_KEY,
	constants.ENV_DASHSCOPE_KEY,
	constants.ENV_ANTHROPIC_BASE,
	constants.ENV_OPENAI_BASE,
	constants.ENV_OLLAMA_HOST,
	constants.ENV_LMSTUDIO_HOST,
	constants.ENV_LLAMACPP_HOST,
}

@(private)
foreign_adoptable_env :: proc(key: string) -> bool {
	for e in FOREIGN_ADOPT_ENVS {
		if e == key {
			return true
		}
	}
	return false
}

@(private)
foreign_env_is_secret :: proc(key: string) -> bool {
	return strings.contains(key, "API_KEY") || strings.contains(key, "_TOKEN")
}

@(private)
foreign_provider :: proc(foreign_id: string) -> (Foreign_Provider, bool) {
	id := strings.to_lower(strings.trim_space(foreign_id), context.temp_allocator)
	for fp in FOREIGN_PROVIDERS {
		for a in fp.aliases {
			if a == id {
				return fp, true
			}
		}
	}
	return {}, false
}

// Best-effort provider guess from a bare model id when a tool does not name
// a provider (aider). Returns "" when nothing matches.
@(private)
foreign_model_provider :: proc(model: string) -> string {
	m := strings.to_lower(strings.trim_space(model), context.temp_allocator)
	switch {
	case strings.has_prefix(m, "claude"), m == "sonnet", m == "opus", m == "haiku":
		return "anthropic"
	case strings.has_prefix(m, "gpt"), strings.has_prefix(m, "o1"),
	     strings.has_prefix(m, "o3"), strings.has_prefix(m, "o4"),
	     strings.has_prefix(m, "codex"):
		return "openai"
	case strings.has_prefix(m, "gemini"):
		return "gemini"
	case strings.has_prefix(m, "grok"):
		return "xai"
	case strings.has_prefix(m, "deepseek"):
		return "deepseek"
	case strings.has_prefix(m, "mistral"), strings.has_prefix(m, "codestral"):
		return "mistral"
	case strings.has_prefix(m, "qwen"):
		return "dashscope"
	case strings.has_prefix(m, "command"):
		return "cohere"
	}
	return ""
}

foreign_enabled :: proc() -> bool {
	if v, ok := os.lookup_env(constants.ENV_ADOPT, context.temp_allocator); ok {
		switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
		case "0", "false", "off", "no":
			return false
		}
	}
	return true
}

@(private)
hint_push :: proc(
	hints: ^[dynamic]Foreign_Hint,
	tool, source, env, value: string,
	secret: bool,
	prio: int,
	mtime: i64,
	require_env := "",
	require_val := "",
) {
	v := strings.trim_space(value)
	if len(env) == 0 || len(v) == 0 {
		return
	}
	if secret && !foreign_key_ok(v) {
		return
	}
	append(hints, Foreign_Hint{
		tool        = strings.clone(tool),
		source      = strings.clone(source),
		env         = strings.clone(env),
		value       = strings.clone(v),
		secret      = secret,
		prio        = prio,
		require_env = strings.clone(require_env),
		require_val = strings.clone(require_val),
		mtime       = mtime,
	})
}

@(private)
note_push :: proc(notes: ^[dynamic]string, tool: string, msg: string) {
	append(notes, strings.clone(fmt.tprintf("%s: %s", tool, msg)))
}

// Emit the standard provider + model vote pair. The model hint only applies
// when this provider actually won the vote (adopted or pre-set in env).
@(private)
hint_provider_model :: proc(
	hints: ^[dynamic]Foreign_Hint,
	tool, source, provider_id, model: string,
	key_env: string,
	mtime: i64,
) {
	if len(provider_id) == 0 {
		return
	}
	require := key_env
	if fp, ok := foreign_provider(provider_id); ok && fp.local {
		require = ""
	}
	hint_push(hints, tool, source, constants.ENV_PROVIDER, provider_id, false, 2, mtime, require_env = require)
	if len(model) > 0 {
		hint_push(hints, tool, source, constants.ENV_MODEL, model, false, 3, mtime,
			require_env = constants.ENV_PROVIDER, require_val = provider_id)
	}
}

// Emit the openai-compat chain for a custom provider a tool configured with
// its own base URL. Key goes to NULLRAY_API_KEY gated on the vote winning so
// a foreign proxy key never leaks into a vendor provider slot.
@(private)
hint_compat_provider :: proc(
	hints: ^[dynamic]Foreign_Hint,
	tool, source, base_url, api_key, model: string,
	mtime: i64,
) {
	base := strings.trim_space(foreign_resolve_value(base_url))
	if len(base) == 0 || strings.contains(base, " ") {
		return
	}
	hint_push(hints, tool, source, constants.ENV_PROVIDER, "openai-compat", false, 2, mtime)
	hint_push(hints, tool, source, constants.ENV_BASE_URL, base, false, 3, mtime,
		require_env = constants.ENV_PROVIDER, require_val = "openai-compat")
	key := foreign_resolve_value(api_key)
	if len(key) > 0 {
		hint_push(hints, tool, source, constants.ENV_API_KEY, key, true, 3, mtime,
			require_env = constants.ENV_PROVIDER, require_val = "openai-compat")
	}
	if len(model) > 0 {
		hint_push(hints, tool, source, constants.ENV_MODEL, model, false, 3, mtime,
			require_env = constants.ENV_PROVIDER, require_val = "openai-compat")
	}
}

foreign_scan :: proc(scan: ^Foreign_Scan) {
	scan.hints = make([dynamic]Foreign_Hint)
	scan.notes = make([dynamic]string)
	foreign_scan_claude(scan)
	foreign_scan_codex(scan)
	foreign_scan_opencode(scan)
	foreign_scan_pi(scan)
	foreign_scan_gemini(scan)
	foreign_scan_qwen(scan)
	foreign_scan_crush(scan)
	foreign_scan_goose(scan)
	foreign_scan_aider(scan)
	foreign_scan_aichat(scan)
	foreign_scan_llm(scan)
}

foreign_scan_destroy :: proc(scan: ^Foreign_Scan) {
	for h in scan.hints {
		delete(h.tool)
		delete(h.source)
		delete(h.env)
		delete(h.value)
		delete(h.require_env)
		delete(h.require_val)
	}
	delete(scan.hints)
	for n in scan.notes {
		delete(n)
	}
	delete(scan.notes)
	scan^ = {}
}

@(private)
foreign_hint_order :: proc(a, b: Foreign_Hint) -> int {
	if a.prio != b.prio {
		return a.prio - b.prio
	}
	if a.mtime != b.mtime {
		return a.mtime < b.mtime ? 1 : -1
	}
	return 0
}

@(private)
foreign_sort_hints :: proc(hints: []Foreign_Hint) {
	slice.stable_sort_by(hints, proc(a, b: Foreign_Hint) -> bool {
		return foreign_hint_order(a, b) < 0
	})
}

@(private)
foreign_env_ready :: proc(h: Foreign_Hint) -> bool {
	v, ok := os.lookup_env(h.env, context.temp_allocator)
	if ok && len(strings.trim_space(v)) > 0 {
		return false
	}
	if len(h.require_env) == 0 {
		return true
	}
	rv, rok := os.lookup_env(h.require_env, context.temp_allocator)
	if !rok || len(strings.trim_space(rv)) == 0 {
		return false
	}
	if len(h.require_val) > 0 && rv != h.require_val {
		return false
	}
	return true
}

// Fill unset env vars from detected foreign configs. Returns owned notes like
// "ANTHROPIC_API_KEY <- claude-code (~/.claude/settings.json)". Caller
// deletes each string and the slice.
foreign_adopt :: proc() -> []string {
	if !foreign_enabled() {
		return nil
	}
	scan: Foreign_Scan
	foreign_scan(&scan)
	defer foreign_scan_destroy(&scan)
	foreign_sort_hints(scan.hints[:])
	applied := make([dynamic]string)
	for h in scan.hints {
		if !foreign_env_ready(h) {
			continue
		}
		os.set_env(h.env, h.value)
		append(&applied, fmt.aprintf("%s <- %s (%s)", h.env, h.tool, h.source))
	}
	return applied[:]
}

// Doctor-facing summary: one line per contributing config file naming the env
// vars it offered, then informational notes. No values are ever included.
foreign_report :: proc(allocator := context.allocator) -> []string {
	lines := make([dynamic]string, allocator)
	if !foreign_enabled() {
		append(&lines, strings.clone("foreign config: disabled (NULLRAY_ADOPT=0)", allocator))
		return lines[:]
	}
	scan: Foreign_Scan
	foreign_scan(&scan)
	defer foreign_scan_destroy(&scan)
	if len(scan.hints) == 0 && len(scan.notes) == 0 {
		append(&lines, strings.clone("foreign config: none found", allocator))
		return lines[:]
	}
	append(&lines, strings.clone("foreign config:", allocator))
	for h in scan.hints {
		append(&lines, strings.clone(fmt.tprintf("  %s %s -> %s", h.tool, h.source, h.env), allocator))
	}
	for n in scan.notes {
		append(&lines, strings.clone(fmt.tprintf("  note: %s", n), allocator))
	}
	return lines[:]
}
