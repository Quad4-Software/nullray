// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
OpenAI-compatible HTTP error formatting.
*/

package provider

import "core:encoding/json"
import "core:fmt"
import "core:strings"
import "nullray:http"

provider_http_error :: proc(res: http.Response, p: ^Provider = nil, allocator := context.allocator) -> string {
	if res.status == 429 {
		if p != nil && p.id == "openrouter" {
			return openrouter_rate_limit_hint(res.body, allocator)
		}
		if msg := extract_provider_error_message(res.body); len(msg) > 0 {
			return fmt.aprintf("rate limited: %s", msg, allocator = allocator)
		}
		return strings.clone("HTTP 429 rate limited (retry later or lower concurrency)", allocator)
	}
	if res.status == 401 {
		if msg := extract_provider_error_message(res.body); len(msg) > 0 {
			if strings.contains(strings.to_lower(msg, context.temp_allocator), "user not found") {
				return strings.clone(
					"HTTP 401 unauthorized: User not found (OpenRouter key revoked or account missing; fix ~/.config/nullray/env)",
					allocator,
				)
			}
			if p != nil && provider_is_local(p.id) {
				return fmt.aprintf(
					"HTTP 401 unauthorized: %s (%s)",
					msg,
					local_auth_hint(p.id),
					allocator = allocator,
				)
			}
			return fmt.aprintf(
				"HTTP 401 unauthorized: %s (check API key in ~/.config/nullray/env)",
				msg,
				allocator = allocator,
			)
		}
		if p != nil && provider_is_local(p.id) {
			return fmt.aprintf("HTTP 401 unauthorized (%s)", local_auth_hint(p.id), allocator = allocator)
		}
		return strings.clone("HTTP 401 unauthorized (check API key in ~/.config/nullray/env)", allocator)
	}
	if msg := extract_provider_error_message(res.body); len(msg) > 0 {
		if p != nil {
			if hint := local_ctx_hint(p.id, msg); len(hint) > 0 {
				return fmt.aprintf("%s%s", msg, hint, allocator = allocator)
			}
		}
		return strings.clone(msg, allocator)
	}
	if res.status == 402 {
		if p != nil && p.id == "openrouter" {
			return strings.clone("HTTP 402 payment required (OpenRouter credits exhausted)", allocator)
		}
		return strings.clone("HTTP 402 payment required (check billing or credits)", allocator)
	}
	if res.status == 404 {
		return strings.clone("HTTP 404 model not found or unavailable", allocator)
	}
	if len(res.err) > 0 {
		return strings.clone(res.err, allocator)
	}
	return fmt.aprintf("HTTP %d", res.status, allocator = allocator)
}

// Actionable auth hint for local servers that enforce a key.
@(private)
local_auth_hint :: proc(id: string) -> string {
	switch id {
	case "llamacpp":
		return "server requires a key; set LLAMA_CPP_API_KEY to match llama-server --api-key"
	case "lmstudio":
		return "server requires a key; set LM_API_TOKEN"
	case "ollama":
		return "server requires auth; check OLLAMA_HOST"
	}
	return "check local server auth"
}

// Suffix for prompt-too-large errors from local servers.
@(private)
local_ctx_hint :: proc(id: string, msg: string) -> string {
	low := strings.to_lower(msg, context.temp_allocator)
	if !strings.contains(low, "context size") &&
	   !strings.contains(low, "context_length") &&
	   !strings.contains(low, "exceed_context") &&
	   !strings.contains(low, "context window") {
		return ""
	}
	switch id {
	case "llamacpp":
		return " (raise llama-server --ctx-size; --parallel divides it across slots)"
	case "ollama":
		return " (raise num_ctx, e.g. OLLAMA_CONTEXT_LENGTH)"
	case "lmstudio":
		return " (raise the model context length in LM Studio)"
	}
	return ""
}

@(private)
extract_provider_error_message :: proc(body: string) -> string {
	if len(body) == 0 {
		return ""
	}
	doc, perr := json.parse_string(body, .JSON, allocator = context.temp_allocator)
	if perr != .None {
		return ""
	}
	obj, ok := doc.(json.Object)
	if !ok {
		return ""
	}
	err_v, has := obj["error"]
	if !has {
		return ""
	}
	if err_obj, eok := err_v.(json.Object); eok {
		if msg, mok := err_obj["message"]; mok {
			if s, sok := msg.(json.String); sok {
				return string(s)
			}
		}
	} else if s, sok := err_v.(json.String); sok {
		return string(s)
	}
	return ""
}
