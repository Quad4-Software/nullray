// SPDX-License-Identifier: 0BSD
/*
OpenAI-compatible request body and header helpers.
*/

package provider

import "core:fmt"
import "core:os"
import "core:strings"
import "nullray:constants"

append_provider_headers :: proc(headers: ^[dynamic]string, p: ^Provider) {
	append(headers, "Content-Type: application/json")
	if len(p.api_key) > 0 {
		if p.id == "azure" {
			append(headers, fmt.tprintf("api-key: %s", p.api_key))
		} else {
			append(headers, fmt.tprintf("Authorization: Bearer %s", p.api_key))
		}
	}
	if p.id == "openrouter" {
		append(headers, "HTTP-Referer: https://github.com/Quad4-Software/nullray")
		append(headers, fmt.tprintf("X-Title: %s", constants.APP_NAME))
	}
	// Local hosts may reject clients without an allowed Origin (403).
	if provider_is_local(p.id) {
		append(headers, "Origin: http://127.0.0.1")
	}
	append_opencode_headers(headers, p)
	if p.id == "anthropic" {
		append(headers, "anthropic-version: 2023-06-01")
	}
	if p.id == "openai" || p.id == "openai-compat" || p.id == "azure" {
		if org, ok := os.lookup_env(constants.ENV_OPENAI_ORG, context.temp_allocator); ok && len(org) > 0 {
			append(headers, fmt.tprintf("OpenAI-Organization: %s", org))
		}
		if proj, ok := os.lookup_env(constants.ENV_OPENAI_PROJECT, context.temp_allocator); ok && len(proj) > 0 {
			append(headers, fmt.tprintf("OpenAI-Project: %s", proj))
		}
	}
}

// Official OpenAI and reasoning models prefer max_completion_tokens.
write_max_tokens_json :: proc(b: ^strings.Builder, p: ^Provider, max_tokens: int, model: string) {
	if max_tokens <= 0 {
		return
	}
	if uses_max_completion_tokens(p, model) {
		fmt.sbprintf(b, `,"max_completion_tokens":%d`, max_tokens)
		return
	}
	fmt.sbprintf(b, `,"max_tokens":%d`, max_tokens)
}

write_sampling_json :: proc(
	b: ^strings.Builder,
	p: ^Provider,
	model: string,
	temperature: f64,
	top_p: f64,
	temperature_set: bool,
	top_p_set: bool,
) {
	if !temperature_set && !top_p_set {
		return
	}
	if !supports_sampling_params(p, model) {
		return
	}
	if temperature_set {
		fmt.sbprintf(b, `,"temperature":%.4g`, temperature)
	}
	if top_p_set {
		fmt.sbprintf(b, `,"top_p":%.4g`, top_p)
	}
}

// Official OpenAI reasoning models and o-series often reject temperature/top_p.
supports_sampling_params :: proc(p: ^Provider, model: string) -> bool {
	m := strings.to_lower(model, context.temp_allocator)
	if strings.has_prefix(m, "o1") || strings.has_prefix(m, "o3") || strings.has_prefix(m, "o4") {
		return false
	}
	if strings.contains(m, "gpt-5") && strings.contains(m, "reason") {
		return false
	}
	_ = p
	return true
}

uses_max_completion_tokens :: proc(p: ^Provider, model: string) -> bool {
	if p != nil && p.id == "openai" {
		return true
	}
	m := strings.to_lower(model, context.temp_allocator)
	if strings.has_prefix(m, "o1") || strings.has_prefix(m, "o3") || strings.has_prefix(m, "o4") {
		return true
	}
	if strings.has_prefix(m, "gpt-5") {
		return true
	}
	return false
}

write_reasoning_json :: proc(b: ^strings.Builder, p: ^Provider, effort: string) {
	e := strings.trim_space(effort)
	if len(e) == 0 {
		return
	}
	el := strings.to_lower(e, context.temp_allocator)
	id := ""
	if p != nil {
		id = p.id
	}
	switch id {
	case "openrouter":
		strings.write_string(b, `,"reasoning":{"effort":`)
		write_json_string(b, el)
		strings.write_string(b, `}`)
	case "cohere":
		co := "high"
		if el == "none" || el == "minimal" {
			co = "none"
		}
		strings.write_string(b, `,"reasoning_effort":`)
		write_json_string(b, co)
	case "dashscope":
		if el == "none" || el == "minimal" {
			strings.write_string(b, `,"enable_thinking":false`)
		} else {
			strings.write_string(b, `,"enable_thinking":true`)
		}
	case "deepseek":
		if el == "none" {
			strings.write_string(b, `,"thinking":{"type":"disabled"}`)
		} else {
			strings.write_string(b, `,"thinking":{"type":"enabled"},"reasoning_effort":`)
			write_json_string(b, map_deepseek_effort(el))
		}
	case "anthropic":
		return
	case "ollama", "lmstudio", "llamacpp", "openai-compat":
		// Local OpenAI-compat servers reject unknown reasoning/thinking fields.
		return
	case:
		strings.write_string(b, `,"reasoning_effort":`)
		write_json_string(b, el)
	}
}

@(private)
map_deepseek_effort :: proc(el: string) -> string {
	switch el {
	case "minimal", "low":
		return "low"
	case "max":
		return "max"
	case:
		return "high"
	}
}

@(private)
cache_enabled :: proc() -> bool {
	if v, ok := os.lookup_env(constants.ENV_CACHE, context.temp_allocator); ok {
		switch strings.to_lower(v, context.temp_allocator) {
		case "0", "false", "off", "no":
			return false
		case "1", "true", "on", "yes", "force":
			return true
		}
	}
	if p, ok := os.lookup_env(constants.ENV_PROVIDER, context.temp_allocator); ok {
		pl := strings.to_lower(p, context.temp_allocator)
		if pl == "openrouter" || strings.contains(pl, "anthropic") {
			return true
		}
	}
	return false
}

@(private)
write_message_json :: proc(b: ^strings.Builder, m: Message, p: ^Provider = nil) {
	strings.write_string(b, `{"role":`)
	write_json_string(b, role_string(m.role))
	if m.role == .Tool {
		if len(m.tool_call_id) > 0 {
			strings.write_string(b, `,"tool_call_id":`)
			write_json_string(b, m.tool_call_id)
		}
		if len(m.name) > 0 {
			strings.write_string(b, `,"name":`)
			write_json_string(b, m.name)
		}
	}
	strings.write_string(b, `,"content":`)
	write_json_string(b, m.content)
	if m.role == .Assistant && len(m.reasoning) > 0 {
		field := assistant_reasoning_json_field(p)
		strings.write_string(b, `,"`)
		strings.write_string(b, field)
		strings.write_string(b, `":`)
		write_json_string(b, m.reasoning)
	}
	if m.cacheable && cache_enabled() && message_cache_control_ok(p) {
		strings.write_string(b, `,"cache_control":{"type":"ephemeral"}`)
	}
	if m.role == .Assistant && len(m.tool_calls) > 0 {
		strings.write_string(b, `,"tool_calls":[`)
		for tc, i in m.tool_calls {
			if i > 0 {
				strings.write_byte(b, ',')
			}
			strings.write_string(b, `{"id":`)
			write_json_string(b, tc.id)
			strings.write_string(b, `,"type":"function","function":{"name":`)
			write_json_string(b, tc.name)
			strings.write_string(b, `,"arguments":`)
			write_json_string(b, tc.arguments)
			strings.write_string(b, `}}`)
		}
		strings.write_byte(b, ']')
	}
	strings.write_byte(b, '}')
}

@(private)
assistant_reasoning_json_field :: proc(p: ^Provider) -> string {
	if p == nil {
		return "reasoning_content"
	}
	switch p.id {
	case "openrouter", "cerebras":
		return "reasoning"
	case:
		return "reasoning_content"
	}
}

@(private)
message_cache_control_ok :: proc(p: ^Provider) -> bool {
	if p == nil {
		return false
	}
	return p.id == "openrouter" || p.id == "anthropic"
}

@(private)
write_json_string :: proc(b: ^strings.Builder, s: string) {
	strings.write_byte(b, '"')
	for r in s {
		switch r {
		case '"':
			strings.write_string(b, `\"`)
		case '\\':
			strings.write_string(b, `\\`)
		case '\n':
			strings.write_string(b, `\n`)
		case '\r':
			strings.write_string(b, `\r`)
		case '\t':
			strings.write_string(b, `\t`)
		case:
			if r < 0x20 {
				fmt.sbprintf(b, `\u%04x`, int(r))
			} else {
				strings.write_rune(b, r)
			}
		}
	}
	strings.write_byte(b, '"')
}
