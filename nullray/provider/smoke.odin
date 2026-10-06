// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Per-model tool-call smoke probe.

A server can list a model as tools-capable (or report no capability data at
all) while the model itself never emits a schema-valid tool call, and the
failure only shows up mid-session as a stalled agent turn. smoke_tool_call
sends one canned non-streamed chat request that demands a single echo_tool
call, then classifies the reply. The verdict is cached process-locally by
provider/model so readiness and probe paths can surface tools: ok|fail|untested
through smoke_result and smoke_label without a second roundtrip.

Opt-in via NULLRAY_MODEL_SMOKE since each run costs one provider roundtrip:
1|on|true|yes runs for every provider, auto runs only for the local/compat
ids whose caps probe has not already confirmed tool support, anything else
(including unset) is off.
*/

package provider

import "base:runtime"
import "core:encoding/json"
import "core:os"
import "core:strings"
import "core:sync"
import "nullray:constants"

Smoke_Result :: enum {
	Untested,
	Pass,
	Fail_No_Call, // no tool_calls in the response at all
	Fail_Invalid, // a call was emitted but not a schema-valid echo_tool one
	Fail_Error,   // provider-level failure (transport, auth, refusal)
	Skipped,      // gated off or nothing callable
}

SMOKE_TOOL_NAME :: "echo_tool"
SMOKE_TOOLS_JSON :: `[{"type":"function","function":{"name":"echo_tool","description":"Echoes text","parameters":{"type":"object","properties":{"text":{"type":"string"}},"required":["text"]}}}]`
SMOKE_SYSTEM_PROMPT :: `You must call the echo_tool with arguments {"text":"ping"}. Do not reply with text.`
SMOKE_USER_PROMPT :: "ping"

@(private)
g_smoke_mu: sync.Mutex
// Verdicts keyed by "provider_id/model": the same model id on two providers
// (ollama vs a compat server) must not share one verdict. The map and its
// keys live on the heap allocator because they outlive any caller context.
@(private)
g_smoke_results: map[string]Smoke_Result

// Cache key for one provider+model pair.
@(private)
smoke_key :: proc(provider_id, model: string, allocator := context.allocator) -> string {
	return strings.concatenate({provider_id, "/", model}, allocator)
}

/*
Run the canned echo_tool task once against p.chat. Pass requires a call named
echo_tool whose arguments parse to a JSON object holding a text key. No
retries: the point is a cheap verdict, not coaxing the model.
*/
smoke_tool_call :: proc(p: ^Provider, model: string, allocator := context.allocator) -> Smoke_Result {
	context.allocator = allocator
	if p == nil || p.chat == nil || len(model) == 0 {
		return .Skipped
	}
	msgs := []Message{
		{role = .System, content = SMOKE_SYSTEM_PROMPT},
		{role = .User, content = SMOKE_USER_PROMPT},
	}
	req := Chat_Request{
		model = model,
		messages = msgs,
		stream = false,
		tools_json = SMOKE_TOOLS_JSON,
		tool_choice = "auto",
		max_tokens = constants.MODEL_SMOKE_MAX_TOKENS,
		temperature = 0,
		temperature_set = true,
	}
	res := p.chat(p, req, allocator)
	defer destroy_chat_response(&res)
	if !res.ok {
		return .Fail_Error
	}
	return smoke_classify(res.tool_calls)
}

smoke_classify :: proc(calls: []Tool_Call) -> Smoke_Result {
	if len(calls) == 0 {
		return .Fail_No_Call
	}
	for tc in calls {
		if tc.name != SMOKE_TOOL_NAME {
			continue
		}
		v, perr := json.parse_string(tc.arguments, .JSON, allocator = context.temp_allocator)
		if perr != .None {
			return .Fail_Invalid
		}
		if obj, ok := v.(json.Object); ok {
			if _, has := obj["text"]; has {
				return .Pass
			}
		}
	}
	// A call happened but none was a valid echo_tool invocation.
	return .Fail_Invalid
}

/*
NULLRAY_MODEL_SMOKE gate. auto restricts to the ids whose tool support comes
from a best-effort local caps probe, and skips the roundtrip when that probe
already confirmed tools. Everything else, including unset, is off.
*/
smoke_enabled :: proc(p: ^Provider = nil) -> bool {
	v, ok := os.lookup_env(constants.ENV_MODEL_SMOKE, context.temp_allocator)
	if !ok {
		return false
	}
	switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
	case "1", "on", "true", "yes":
		return true
	case "auto":
		if p == nil {
			return false
		}
		switch p.id {
		case "ollama", "llamacpp", "lmstudio", "openai-compat":
		case:
			return false
		}
		return !(p.caps.tools_known && p.caps.supports_tools)
	}
	return false
}

// Last cached verdict for provider_id+model; ok is false when that pair was
// never smoked.
smoke_result :: proc(provider_id, model: string) -> (Smoke_Result, bool) {
	sync.mutex_lock(&g_smoke_mu)
	defer sync.mutex_unlock(&g_smoke_mu)
	if g_smoke_results == nil {
		return .Untested, false
	}
	key := smoke_key(provider_id, model, context.temp_allocator)
	r, ok := g_smoke_results[key]
	return r, ok
}

/*
Entry point for readiness/probe: returns the cached verdict when present,
returns Skipped without calling the provider when gated off, else runs the
smoke once and caches it under provider_id/model.
*/
smoke_run_if_enabled :: proc(p: ^Provider, model: string, allocator := context.allocator) -> Smoke_Result {
	if p == nil || len(model) == 0 {
		return .Skipped
	}
	if r, ok := smoke_result(p.id, model); ok {
		return r
	}
	if !smoke_enabled(p) {
		return .Skipped
	}
	r := smoke_tool_call(p, model, allocator)
	smoke_cache_put(smoke_key(p.id, model, context.temp_allocator), r)
	return r
}

smoke_label :: proc(r: Smoke_Result) -> string {
	switch r {
	case .Pass:
		return "ok"
	case .Fail_No_Call:
		return "no-call"
	case .Fail_Invalid:
		return "invalid"
	case .Fail_Error:
		return "error"
	case .Skipped:
		return "skipped"
	case .Untested:
		return "untested"
	}
	return "untested"
}

@(private)
smoke_cache_put :: proc(key: string, r: Smoke_Result) {
	sync.mutex_lock(&g_smoke_mu)
	defer sync.mutex_unlock(&g_smoke_mu)
	if g_smoke_results == nil {
		g_smoke_results = make(map[string]Smoke_Result, runtime.heap_allocator())
	}
	// Update in place so the borrowed caller string never lands in the map.
	for k in g_smoke_results {
		if k == key {
			g_smoke_results[k] = r
			return
		}
	}
	g_smoke_results[strings.clone(key, runtime.heap_allocator())] = r
}

// Test hook: drop every cached verdict.
smoke_cache_reset :: proc() {
	sync.mutex_lock(&g_smoke_mu)
	defer sync.mutex_unlock(&g_smoke_mu)
	for k in g_smoke_results {
		delete(k, runtime.heap_allocator())
	}
	delete(g_smoke_results)
	g_smoke_results = nil
}
