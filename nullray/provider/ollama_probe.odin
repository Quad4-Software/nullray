// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Local model capability and context probing.

Ollama silently truncates conversation history once it exceeds the server side
context window (default num_ctx is 4096) and surfaces no error, so an agent can
burn many turns re-reading dropped history. This file probes /api/show and
/api/ps for model capabilities and the live window, then pins an explicit
num_ctx on chat requests. llama.cpp exposes the same facts via GET /props.

The caps record and pure parsers live in local_caps.odin; this file is the IO
and resolution side.
*/

package provider

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:sync"
import "nullray:constants"
import "nullray:http"

// Cap on auto num_ctx when only the trained context length is known: the KV
// cache grows linearly with num_ctx and most local models degrade well before
// their full window.
OLLAMA_NUM_CTX_CAP :: 32_768

/*
Probe /api/show and /api/ps once per (provider, model). Honors
NULLRAY_LOCAL_PROBE=0 for offline posture; the endpoint is the configured
local server, same as the readiness probes in local.odin.
*/
ollama_ensure_caps :: proc(p: ^Provider, model: string, timeout_sec := 3) {
	if p == nil || p.id != "ollama" || !local_probe_enabled_from_env() {
		return
	}
	m := model
	if len(m) == 0 {
		m = p.default_model
	}
	if p.caps.probed && p.caps.probed_model == m {
		return
	}
	root := openai_compat_root(p.base_url)
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	strings.write_string(&b, `{"name":`)
	write_json_string(&b, m)
	strings.write_string(&b, `,"model":`)
	write_json_string(&b, m)
	strings.write_byte(&b, '}')
	headers := make([dynamic]string, context.temp_allocator)
	append_provider_headers(&headers, p)
	res := http.post_json(
		http.join_url(root, "/api/show"),
		headers[:],
		strings.to_string(b),
		timeout_sec,
		context.temp_allocator,
	)

	local_caps_destroy(&p.caps)
	// Only a successful probe marks probed: a refused connection is cheap to
	// retry next request, and a server that comes up mid-session should get
	// real caps instead of staying on the fallback window.
	if res.ok {
		p.caps = parse_ollama_show_body(res.body)
		p.caps.probed = true
		p.caps.probed_model = strings.clone(m)
		ps := http.get(http.join_url(root, "/api/ps"), nil, timeout_sec, context.temp_allocator)
		if ps.ok {
			p.caps.loaded_ctx = parse_ollama_ps_context(ps.body, m)
		}
		ollama_caps_warn_small_ctx(p)
	}
}

/*
Probe GET /props once per provider instance. The endpoint is the configured
llama-server base, same host the chat path already talks to.
*/
llamacpp_ensure_caps :: proc(p: ^Provider, timeout_sec := 3) {
	if p == nil || p.id != "llamacpp" || !local_probe_enabled_from_env() || p.caps.probed {
		return
	}
	root := openai_compat_root(p.base_url)
	res := http.get(http.join_url(root, "/props"), nil, timeout_sec, context.temp_allocator)
	local_caps_destroy(&p.caps)
	if res.ok {
		p.caps = parse_llamacpp_props_body(res.body)
		p.caps.probed = true
		p.caps.probed_model = strings.clone(p.default_model)
	}
}

provider_ensure_caps :: proc(p: ^Provider, model := "") {
	if p == nil {
		return
	}
	switch p.id {
	case "ollama":
		ollama_ensure_caps(p, model)
	case "llamacpp":
		llamacpp_ensure_caps(p)
	}
	// Opt-in canned tool-call probe (NULLRAY_MODEL_SMOKE). The result caches
	// per model so this costs at most one extra chat per model.
	m := model
	if len(m) == 0 {
		m = p.default_model
	}
	if len(m) > 0 {
		smoke_run_if_enabled(p, m)
	}
}

@(private)
g_small_ctx_warned: map[string]bool
@(private)
g_caps_warn_mu: sync.Mutex

/*
Warn once per provider+model when the effective window is below the agent
floor. Same posture as openrouter_zdr_maybe_warn: stderr note, never blocks.
*/
ollama_caps_warn_small_ctx :: proc(p: ^Provider) {
	n := ollama_num_ctx_from_caps(&p.caps)
	if n <= 0 || n >= constants.OLLAMA_MIN_AGENT_CTX {
		return
	}
	key := fmt.tprintf("%s|%s", p.id, p.caps.probed_model)
	sync.mutex_lock(&g_caps_warn_mu)
	defer sync.mutex_unlock(&g_caps_warn_mu)
	if g_small_ctx_warned == nil {
		// Process-lifetime state: heap allocator, never a caller context.
		g_small_ctx_warned = make(map[string]bool, runtime.heap_allocator())
	}
	if g_small_ctx_warned[key] {
		return
	}
	g_small_ctx_warned[strings.clone(key, runtime.heap_allocator())] = true
	fmt.eprintf(
		"nullray: %s model %s context %d below agent floor %d; raise num_ctx via Modelfile PARAMETER or %s\n",
		p.id,
		p.caps.probed_model,
		n,
		constants.OLLAMA_MIN_AGENT_CTX,
		constants.ENV_OLLAMA_NUM_CTX,
	)
}

/*
num_ctx to send for an ollama chat request; <=0 means send nothing.
NULLRAY_OLLAMA_NUM_CTX wins outright and <=0 opts out. Otherwise ensure the
probe ran and resolve from caps.
*/
ollama_num_ctx :: proc(p: ^Provider, model: string) -> int {
	if v, ok := os.lookup_env(constants.ENV_OLLAMA_NUM_CTX, context.temp_allocator); ok {
		if n, nok := strconv.parse_int(strings.trim_space(v)); nok {
			return n
		}
	}
	ollama_ensure_caps(p, model)
	return ollama_num_ctx_from_caps(&p.caps)
}

/*
Resolution order: Modelfile num_ctx (explicit user config, honored as-is),
then min(model context_length, 32k), then a 16k agent floor. A live server
window larger than any of these is honored, but a smaller one never shrinks
the computed value: the /api/ps default of 4096 is exactly the silent
truncation trap this exists to fix.
*/
ollama_num_ctx_from_caps :: proc(caps: ^Local_Caps) -> int {
	n := caps.modelfile_num_ctx
	if n <= 0 {
		if caps.context_length > 0 {
			n = min(caps.context_length, OLLAMA_NUM_CTX_CAP)
		} else {
			n = constants.OLLAMA_MIN_AGENT_CTX
		}
	}
	if caps.loaded_ctx > n {
		n = caps.loaded_ctx
	}
	return n
}

/*
Ollama drops conversation history past the server side window (default
num_ctx 4096) with no error, so pin an explicit window on every chat request.
Newer Ollama forwards a top level num_ctx into options on
/v1/chat/completions (ollama PR 16825); options.num_ctx covers handlers that
read the native shape. Both are ignored harmlessly by builds that support
neither.
*/
write_ollama_num_ctx_json :: proc(b: ^strings.Builder, p: ^Provider, model: string) {
	n := ollama_num_ctx(p, model)
	if n <= 0 {
		return
	}
	// Braces stay out of sbprintf format strings; fmt treats { as a directive.
	fmt.sbprintf(b, `,"num_ctx":%d`, n)
	strings.write_string(b, `,"options":{"num_ctx":`)
	fmt.sbprintf(b, `%d`, n)
	strings.write_byte(b, '}')
}
