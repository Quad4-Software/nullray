// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package config

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"
import "nullray:constants"

@(private)
ft_home :: proc(t: ^testing.T, name: string) -> string {
	tmp, terr := os.temp_directory(context.temp_allocator)
	testing.expect(t, terr == nil)
	dir, jerr := filepath.join({tmp, fmt.tprintf("nullray-foreign-%d-%s", os.get_pid(), name)}, context.temp_allocator)
	testing.expect(t, jerr == nil)
	_ = os.make_directory_all(dir)
	return dir
}

@(private)
ft_env :: proc(dir: string) {
	os.set_env("HOME", dir)
	os.set_env("XDG_CONFIG_HOME", foreign_join(dir, ".config"))
	os.set_env("XDG_DATA_HOME", foreign_join(dir, ".local", "share"))
}

@(private)
ft_write :: proc(t: ^testing.T, path, body: string) {
	dir := filepath.dir(path)
	_ = os.make_directory_all(dir)
	testing.expect(t, os.write_entire_file(path, transmute([]byte)body) == nil)
}

@(private)
ft_unset :: proc(keys: ..string) {
	for k in keys {
		os.unset_env(k)
	}
}

@(private)
ft_clear :: proc() {
	ft_unset(
		constants.ENV_PROVIDER, constants.ENV_MODEL, constants.ENV_BASE_URL,
		constants.ENV_API_KEY, constants.ENV_REASONING,
		constants.ENV_ANTHROPIC_KEY, constants.ENV_ANTHROPIC_BASE,
		constants.ENV_OPENAI_KEY, constants.ENV_OPENAI_BASE,
		constants.ENV_GEMINI_KEY, constants.ENV_OPENROUTER_KEY,
		constants.ENV_OPENCODE_KEY, constants.ENV_MISTRAL_KEY,
		constants.ENV_DASHSCOPE_KEY, constants.ENV_ADOPT,
	)
}

@(test)
test_foreign_opencode_auth_adopts_keys :: proc(t: ^testing.T) {
	dir := ft_home(t, "opencode-auth")
	ft_env(dir)
	defer ft_clear()
	ft_clear()

	auth := `{"anthropic": {"type": "api", "key": "sk-ant-foreign-1"},
		"openai": {"type": "api", "key": "sk-foreign-2"},
		"github-copilot": {"type": "oauth", "access": "gho_x", "expires": 0}}`
	ft_write(t, foreign_join(dir, ".local", "share", "opencode", "auth.json"), auth)

	notes := foreign_adopt()
	defer {
		for n in notes { delete(n) }
		delete(notes)
	}
	v, ok := os.lookup_env(constants.ENV_ANTHROPIC_KEY, context.temp_allocator)
	testing.expect(t, ok && v == "sk-ant-foreign-1")
	v2, ok2 := os.lookup_env(constants.ENV_OPENAI_KEY, context.temp_allocator)
	testing.expect(t, ok2 && v2 == "sk-foreign-2")
	// oauth for an unknown provider must not leak anywhere
	_, cop := os.lookup_env("COPILOT_GITHUB_TOKEN", context.temp_allocator)
	testing.expect(t, !cop)
	testing.expect(t, len(notes) >= 2)
}

@(test)
test_foreign_claude_settings_env_and_model :: proc(t: ^testing.T) {
	dir := ft_home(t, "claude")
	ft_env(dir)
	defer ft_clear()
	ft_clear()

	settings := `{"env": {"ANTHROPIC_API_KEY": "sk-ant-cfg-9", "ANTHROPIC_BASE_URL": "https://proxy.example.com"},
		"model": "claude-sonnet-4-5"}`
	ft_write(t, foreign_join(dir, ".claude", "settings.json"), settings)

	notes := foreign_adopt()
	defer {
		for n in notes { delete(n) }
		delete(notes)
	}
	v, _ := os.lookup_env(constants.ENV_ANTHROPIC_KEY, context.temp_allocator)
	testing.expect_value(t, v, "sk-ant-cfg-9")
	b, _ := os.lookup_env(constants.ENV_ANTHROPIC_BASE, context.temp_allocator)
	testing.expect_value(t, b, "https://proxy.example.com")
	p, _ := os.lookup_env(constants.ENV_PROVIDER, context.temp_allocator)
	testing.expect_value(t, p, "anthropic")
	m, _ := os.lookup_env(constants.ENV_MODEL, context.temp_allocator)
	testing.expect_value(t, m, "claude-sonnet-4-5")
}

@(test)
test_foreign_provider_vote_requires_key :: proc(t: ^testing.T) {
	dir := ft_home(t, "vote-nokey")
	ft_env(dir)
	defer ft_clear()
	ft_clear()

	// Model configured but no anthropic key anywhere: no provider vote.
	settings := `{"model": "claude-sonnet-4-5"}`
	ft_write(t, foreign_join(dir, ".claude", "settings.json"), settings)

	notes := foreign_adopt()
	defer {
		for n in notes { delete(n) }
		delete(notes)
	}
	_, ok := os.lookup_env(constants.ENV_PROVIDER, context.temp_allocator)
	testing.expect(t, !ok)
	_, mok := os.lookup_env(constants.ENV_MODEL, context.temp_allocator)
	testing.expect(t, !mok)
}

@(test)
test_foreign_never_overrides_env :: proc(t: ^testing.T) {
	dir := ft_home(t, "nooverride")
	ft_env(dir)
	defer ft_clear()
	ft_clear()

	os.set_env(constants.ENV_ANTHROPIC_KEY, "sk-ant-mine")
	defer os.unset_env(constants.ENV_ANTHROPIC_KEY)
	auth := `{"anthropic": {"type": "api", "key": "sk-ant-other"}}`
	ft_write(t, foreign_join(dir, ".local", "share", "opencode", "auth.json"), auth)

	notes := foreign_adopt()
	defer {
		for n in notes { delete(n) }
		delete(notes)
	}
	v, _ := os.lookup_env(constants.ENV_ANTHROPIC_KEY, context.temp_allocator)
	testing.expect_value(t, v, "sk-ant-mine")
}

@(test)
test_foreign_codex_custom_provider :: proc(t: ^testing.T) {
	dir := ft_home(t, "codex")
	ft_env(dir)
	defer ft_clear()
	ft_clear()

	ft_write(t, foreign_join(dir, ".codex", "auth.json"),
		`{"OPENAI_API_KEY": "sk-codex-1"}`)
	cfg := `model = "my-model-7"
model_provider = "lantern"

[model_providers.lantern]
name = "Lantern"
base_url = "https://lantern.example.com/v1"
env_key = "LANTERN_API_KEY"
wire_api = "chat"
`
	ft_write(t, foreign_join(dir, ".codex", "config.toml"), cfg)
	os.set_env("LANTERN_API_KEY", "sk-lantern-8")
	defer os.unset_env("LANTERN_API_KEY")

	notes := foreign_adopt()
	defer {
		for n in notes { delete(n) }
		delete(notes)
	}
	p, _ := os.lookup_env(constants.ENV_PROVIDER, context.temp_allocator)
	testing.expect_value(t, p, "openai-compat")
	b, _ := os.lookup_env(constants.ENV_BASE_URL, context.temp_allocator)
	testing.expect_value(t, b, "https://lantern.example.com/v1")
	k, _ := os.lookup_env(constants.ENV_API_KEY, context.temp_allocator)
	testing.expect_value(t, k, "sk-lantern-8")
	m, _ := os.lookup_env(constants.ENV_MODEL, context.temp_allocator)
	testing.expect_value(t, m, "my-model-7")
}

@(test)
test_foreign_pi_settings_and_auth :: proc(t: ^testing.T) {
	dir := ft_home(t, "pi")
	ft_env(dir)
	defer ft_clear()
	ft_clear()

	agent := foreign_join(dir, ".pi", "agent")
	ft_write(t, foreign_join(agent, "auth.json"),
		`{"anthropic": {"type": "api_key", "key": "sk-ant-pi-3"},
		  "openai": {"type": "api_key", "key": "!secret-tool print"}}`)
	ft_write(t, foreign_join(agent, "settings.json"),
		`{"defaultProvider": "anthropic", "defaultModel": "claude-opus-4-1", "defaultThinkingLevel": "high"}`)

	notes := foreign_adopt()
	defer {
		for n in notes { delete(n) }
		delete(notes)
	}
	v, _ := os.lookup_env(constants.ENV_ANTHROPIC_KEY, context.temp_allocator)
	testing.expect_value(t, v, "sk-ant-pi-3")
	p, _ := os.lookup_env(constants.ENV_PROVIDER, context.temp_allocator)
	testing.expect_value(t, p, "anthropic")
	m, _ := os.lookup_env(constants.ENV_MODEL, context.temp_allocator)
	testing.expect_value(t, m, "claude-opus-4-1")
	r, _ := os.lookup_env(constants.ENV_REASONING, context.temp_allocator)
	testing.expect_value(t, r, "high")
	// command indirections are never executed
	_, ok := os.lookup_env(constants.ENV_OPENAI_KEY, context.temp_allocator)
	testing.expect(t, !ok)
}

@(test)
test_foreign_gemini_dotenv :: proc(t: ^testing.T) {
	dir := ft_home(t, "gemini")
	ft_env(dir)
	defer ft_clear()
	ft_clear()

	ft_write(t, foreign_join(dir, ".gemini", ".env"),
		"GEMINI_API_KEY=\"g-em-key-4\"\nOTHER=nope\n")
	ft_write(t, foreign_join(dir, ".gemini", "settings.json"),
		`{"security": {"auth": {"selectedType": "gemini-api-key"}}, "model": {"name": "gemini-3-flash"}}`)

	notes := foreign_adopt()
	defer {
		for n in notes { delete(n) }
		delete(notes)
	}
	v, _ := os.lookup_env(constants.ENV_GEMINI_KEY, context.temp_allocator)
	testing.expect_value(t, v, "g-em-key-4")
	p, _ := os.lookup_env(constants.ENV_PROVIDER, context.temp_allocator)
	testing.expect_value(t, p, "gemini")
	m, _ := os.lookup_env(constants.ENV_MODEL, context.temp_allocator)
	testing.expect_value(t, m, "gemini-3-flash")
}

@(test)
test_foreign_qwen_env_map_dashscope :: proc(t: ^testing.T) {
	dir := ft_home(t, "qwen")
	ft_env(dir)
	defer ft_clear()
	ft_clear()

	settings := `{
		"modelProviders": {"openai": [{"id": "qwen3-coder-plus", "baseUrl": "https://dashscope.aliyuncs.com/compatible-mode/v1", "envKey": "DASHSCOPE_API_KEY"}]},
		"env": {"DASHSCOPE_API_KEY": "sk-dash-6"},
		"security": {"auth": {"selectedType": "openai"}},
		"model": {"name": "qwen3-coder-plus"}}`
	ft_write(t, foreign_join(dir, ".qwen", "settings.json"), settings)

	notes := foreign_adopt()
	defer {
		for n in notes { delete(n) }
		delete(notes)
	}
	v, _ := os.lookup_env(constants.ENV_DASHSCOPE_KEY, context.temp_allocator)
	testing.expect_value(t, v, "sk-dash-6")
	p, _ := os.lookup_env(constants.ENV_PROVIDER, context.temp_allocator)
	testing.expect_value(t, p, "dashscope")
	m, _ := os.lookup_env(constants.ENV_MODEL, context.temp_allocator)
	testing.expect_value(t, m, "qwen3-coder-plus")
}

@(test)
test_foreign_aider_conf :: proc(t: ^testing.T) {
	dir := ft_home(t, "aider")
	ft_env(dir)
	defer ft_clear()
	ft_clear()

	conf := `
model: anthropic/claude-sonnet-4-5
api-key:
  - anthropic=sk-ant-aid-7
  - openai=sk-aid-2
`
	ft_write(t, foreign_join(dir, ".aider.conf.yml"), conf)

	notes := foreign_adopt()
	defer {
		for n in notes { delete(n) }
		delete(notes)
	}
	v, _ := os.lookup_env(constants.ENV_ANTHROPIC_KEY, context.temp_allocator)
	testing.expect_value(t, v, "sk-ant-aid-7")
	o, _ := os.lookup_env(constants.ENV_OPENAI_KEY, context.temp_allocator)
	testing.expect_value(t, o, "sk-aid-2")
	p, _ := os.lookup_env(constants.ENV_PROVIDER, context.temp_allocator)
	testing.expect_value(t, p, "anthropic")
	m, _ := os.lookup_env(constants.ENV_MODEL, context.temp_allocator)
	testing.expect_value(t, m, "claude-sonnet-4-5")
}

@(test)
test_foreign_llm_keys :: proc(t: ^testing.T) {
	dir := ft_home(t, "llm")
	ft_env(dir)
	defer ft_clear()
	ft_clear()

	keys := `{"mistral": "mist-key-9", "// note": "ignore me"}`
	ft_write(t, foreign_join(dir, ".config", "io.datasette.llm", "keys.json"), keys)

	notes := foreign_adopt()
	defer {
		for n in notes { delete(n) }
		delete(notes)
	}
	v, _ := os.lookup_env(constants.ENV_MISTRAL_KEY, context.temp_allocator)
	testing.expect_value(t, v, "mist-key-9")
}

@(test)
test_foreign_adopt_disabled :: proc(t: ^testing.T) {
	dir := ft_home(t, "disabled")
	ft_env(dir)
	defer ft_clear()
	ft_clear()

	os.set_env(constants.ENV_ADOPT, "0")
	auth := `{"anthropic": {"type": "api", "key": "sk-ant-off"}}`
	ft_write(t, foreign_join(dir, ".local", "share", "opencode", "auth.json"), auth)

	notes := foreign_adopt()
	testing.expect(t, len(notes) == 0)
	_, ok := os.lookup_env(constants.ENV_ANTHROPIC_KEY, context.temp_allocator)
	testing.expect(t, !ok)
}

@(test)
test_foreign_jsonc_config :: proc(t: ^testing.T) {
	dir := ft_home(t, "jsonc")
	ft_env(dir)
	defer ft_clear()
	ft_clear()

	cfg := `{
		// pick the custom relay
		"model": "relay/fast-1",
		"provider": {
			"relay": {
				"npm": "@ai-sdk/openai-compatible",
				"options": {"baseURL": "https://relay.example.com/v1", "apiKey": "sk-relay-5"},
			},
		},
	}`
	ft_write(t, foreign_join(dir, ".config", "opencode", "opencode.json"), cfg)

	notes := foreign_adopt()
	defer {
		for n in notes { delete(n) }
		delete(notes)
	}
	p, _ := os.lookup_env(constants.ENV_PROVIDER, context.temp_allocator)
	testing.expect_value(t, p, "openai-compat")
	b, _ := os.lookup_env(constants.ENV_BASE_URL, context.temp_allocator)
	testing.expect_value(t, b, "https://relay.example.com/v1")
	k, _ := os.lookup_env(constants.ENV_API_KEY, context.temp_allocator)
	testing.expect_value(t, k, "sk-relay-5")
	m, _ := os.lookup_env(constants.ENV_MODEL, context.temp_allocator)
	testing.expect_value(t, m, "fast-1")
}

@(test)
test_foreign_report_lists_sources :: proc(t: ^testing.T) {
	dir := ft_home(t, "report")
	ft_env(dir)
	defer ft_clear()
	ft_clear()

	ft_write(t, foreign_join(dir, ".local", "share", "opencode", "auth.json"),
		`{"groq": {"type": "api", "key": "gsk-test-1"}}`)

	lines := foreign_report()
	defer {
		for l in lines { delete(l) }
		delete(lines)
	}
	joined := strings.join(lines, "\n", context.temp_allocator)
	testing.expect(t, strings.contains(joined, "opencode"))
	testing.expect(t, strings.contains(joined, "GROQ_API_KEY"))
	// no secret value leaks into the report
	testing.expect(t, !strings.contains(joined, "gsk-test-1"))
}
