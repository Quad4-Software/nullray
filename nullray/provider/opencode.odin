// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
OpenCode Zen and Go request headers for routing and session affinity, plus
per-model API surface dispatch (chat/completions, messages, responses).
*/

package provider

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "core:time"

@(private)
g_opencode_session: string

@(private)
g_opencode_fallback: string

@(private)
g_opencode_mu: sync.Mutex

// Bind the live conversation id used for x-opencode-session.
// Chat workers override this per request via Chat_Request.session_id, so a
// background tab never carries another tab's session id.
set_session :: proc(session_id: string) {
	sync.mutex_lock(&g_opencode_mu)
	defer sync.mutex_unlock(&g_opencode_mu)
	delete(g_opencode_session, runtime.heap_allocator())
	g_opencode_session = ""
	if len(session_id) > 0 {
		g_opencode_session = strings.clone(session_id, runtime.heap_allocator())
	}
}

clear_session :: proc() {
	sync.mutex_lock(&g_opencode_mu)
	defer sync.mutex_unlock(&g_opencode_mu)
	delete(g_opencode_session, runtime.heap_allocator())
	g_opencode_session = ""
	delete(g_opencode_fallback, runtime.heap_allocator())
	g_opencode_fallback = ""
}

@(private)
opencode_affinity_id :: proc(explicit: string) -> string {
	if len(explicit) > 0 {
		return explicit
	}
	sync.mutex_lock(&g_opencode_mu)
	defer sync.mutex_unlock(&g_opencode_mu)
	if len(g_opencode_session) > 0 {
		return g_opencode_session
	}
	if len(g_opencode_fallback) == 0 {
		g_opencode_fallback = fmt.aprintf("nullray-%d-%d", os.get_pid(), time.now()._nsec, allocator = runtime.heap_allocator())
	}
	return g_opencode_fallback
}

@(private)
is_opencode_provider :: proc(p: ^Provider) -> bool {
	if p == nil {
		return false
	}
	return p.id == "opencode" || p.id == "opencode-go"
}

@(private)
append_opencode_headers :: proc(headers: ^[dynamic]string, p: ^Provider, session_id := "") {
	if !is_opencode_provider(p) {
		return
	}
	append(headers, fmt.tprintf("x-opencode-session: %s", opencode_affinity_id(session_id)))
}

/*
Zen is multi-protocol: model families map to different endpoints
(https://opencode.ai/docs/zen). The models.dev catalog (same schema the
OpenCode v2 model list serves) carries the authoritative surface via each
model's npm package, prefix rules below are the offline fallback. Zen and Go
do differ: on Go, qwen3.x is chat/completions except qwen3.8-flash, and
minimax-m3/m2.7 ride messages.
*/
Opencode_Api :: enum {
	Chat,
	Messages,
	Responses,
	Gemini,
	SystemOne,
}

@(private)
opencode_npm_to_api :: proc(npm: string) -> Opencode_Api {
	switch npm {
	case "@ai-sdk/anthropic":
		return .Messages
	case "@ai-sdk/openai":
		return .Responses
	case "@ai-sdk/google":
		return .Gemini
	}
	return .Chat
}

@(private)
opencode_fallback_api :: proc(provider_id, model: string) -> Opencode_Api {
	m := strings.to_lower(strings.trim_space(model), context.temp_allocator)
	switch {
	case strings.has_prefix(m, "claude-"):
		return .Messages
	case strings.has_prefix(m, "jev-"):
		return .SystemOne
	case strings.has_prefix(m, "gpt-"),
	     strings.has_prefix(m, "grok-"),
	     strings.has_prefix(m, "muse-"):
		return .Responses
	case strings.has_prefix(m, "gemini-"):
		return .Gemini
	}
	if provider_id == "opencode-go" {
		switch m {
		case "qwen3.8-flash", "minimax-m3", "minimax-m2.7":
			return .Messages
		}
		return .Chat
	}
	switch {
	case m == "qwen3.8-max":
		return .Chat
	case strings.has_prefix(m, "qwen"):
		return .Messages
	}
	return .Chat
}

opencode_model_api :: proc(provider_id, model: string) -> Opencode_Api {
	m := strings.to_lower(strings.trim_space(model), context.temp_allocator)
	// jev is a bespoke systemone endpoint the catalog marks no npm package for.
	if strings.has_prefix(m, "jev-") {
		return .SystemOne
	}
	if npm := modelsdev_npm(provider_id, m); len(npm) > 0 {
		return opencode_npm_to_api(npm)
	}
	return opencode_fallback_api(provider_id, m)
}

// Short surface label for /models annotations. Empty for chat/completions.
opencode_api_label :: proc(provider_id, model: string) -> string {
	switch opencode_model_api(provider_id, model) {
	case .Messages:
		return "messages"
	case .Responses:
		return "responses"
	case .Gemini:
		return "gemini"
	case .SystemOne:
		return "systemone"
	case .Chat:
	}
	return ""
}

@(private)
opencode_is_zen_base :: proc(p: ^Provider) -> bool {
	return p != nil && strings.contains(p.base_url, "opencode.ai/zen")
}

@(private)
opencode_unsupported_err :: proc(p: ^Provider, model: string, api: Opencode_Api, allocator := context.allocator) -> string {
	if api == .SystemOne {
		return fmt.aprintf(
			"%s rides the Zen systemone endpoint: it is a typed question evaluator (state + questions), not a chat model, so it cannot drive an agent turn. Pick any other Zen model.",
			model,
			allocator = allocator,
		)
	}
	return fmt.aprintf(
		"%s uses the Zen %s endpoint, which nullray does not support yet. Pick a chat model (big-pickle, kimi, glm, minimax, deepseek, qwen3.8-max) or a claude/qwen model for messages.",
		model,
		opencode_api_label(p.id, model),
		allocator = allocator,
	)
}

@(private)
opencode_wrap_error :: proc(res_in: Chat_Response, model: string, api: Opencode_Api, p: ^Provider, allocator := context.allocator) -> Chat_Response {
	res := res_in
	if res.ok || len(res.err) == 0 {
		return res
	}
	low := strings.to_lower(res.err, context.temp_allocator)
	if !strings.contains(low, "protocol") {
		return res
	}
	hint := opencode_unsupported_err(p, model, api, allocator)
	delete(res.err)
	res.err = hint
	return res
}

// Fetch the live list plus models.dev enrichment (context limit, cost) used
// for surface routing and the /models display.
opencode_list_models :: proc(p: ^Provider, allocator := context.allocator) -> (models: []Model_Info, err: string) {
	modelsdev_refresh_if_stale()
	models, err = openai_list_models(p, allocator)
	if len(err) > 0 {
		return
	}
	modelsdev_enrich(p.id, models)
	return
}

opencode_chat :: proc(p: ^Provider, req: Chat_Request, allocator := context.allocator) -> Chat_Response {
	model := req.model
	if len(model) == 0 {
		model = p.default_model
	}
	api := opencode_model_api(p.id, model)
	// Model-based routing only applies on the real Zen host. A custom base
	// may be a proxy that normalizes everything to chat/completions.
	if is_opencode_provider(p) && opencode_is_zen_base(p) {
		#partial switch api {
		case .Messages:
			return anthropic_chat(p, req, allocator)
		case .Responses:
			return responses_chat(p, req, allocator)
		case .Gemini:
			return gemini_chat(p, req, allocator)
		case .SystemOne:
			return Chat_Response{ok = false, err = opencode_unsupported_err(p, model, api, allocator)}
		}
		return openai_chat(p, req, allocator)
	}
	res := openai_chat(p, req, allocator)
	return opencode_wrap_error(res, model, api, p, allocator)
}

opencode_chat_stream :: proc(
	p: ^Provider,
	req: Chat_Request,
	on_delta: Delta_Proc,
	user: rawptr,
	allocator := context.allocator,
) -> Chat_Response {
	model := req.model
	if len(model) == 0 {
		model = p.default_model
	}
	api := opencode_model_api(p.id, model)
	if is_opencode_provider(p) && opencode_is_zen_base(p) {
		#partial switch api {
		case .Messages:
			return anthropic_chat_stream(p, req, on_delta, user, allocator)
		case .Responses:
			return responses_chat_stream(p, req, on_delta, user, allocator)
		case .Gemini:
			return gemini_chat_stream(p, req, on_delta, user, allocator)
		case .SystemOne:
			return Chat_Response{ok = false, err = opencode_unsupported_err(p, model, api, allocator)}
		}
		return openai_chat_stream(p, req, on_delta, user, allocator)
	}
	res := openai_chat_stream(p, req, on_delta, user, allocator)
	return opencode_wrap_error(res, model, api, p, allocator)
}
