// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Per-model request profiles loaded from model_profiles.json.

Sources merge in precedence order, first matching profile wins:
  <config dir>/model_profiles.json
  <workspace>/.nullray/model_profiles.json

Shape:
  {"profiles":[
    {"match":"qwen*","ctx":128000,"num_ctx":32768,"temperature":0.6,
     "reasoning":"off","one_tool_per_turn":true,"prompt_tier":"lean",
     "parallel_tool_calls":false,"constrained_tools":true,
     "constrained_mode":"shape"}
  ]}

Profiles only fill fields the request did not pin down (the *_set flags on
Chat_Request mark explicit CLI/env values). num_ctx flows through the ollama
write path in openai_compat.odin with NULLRAY_OLLAMA_NUM_CTX still winning
outright, including a <=0 opt-out. JSON parse/serialize live in
model_profile_json.odin.

quant_family ("llama"|"qwen") and quant_tier ("low"|"mid"|"high" or a raw
tag like "q4_k_m") override the values sniffed from the model id or GGUF
filename by the tool-turn temperature clamp in sampling_gguf.odin.
*/

package provider

import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:time"
import "nullray:constants"
import "nullray:sandbox"

Profile_Reasoning :: enum {
	Unset,
	Off,
	On,
}

Profile_Prompt_Tier :: enum {
	Unset,
	Tiny,
	Lean,
	Full,
}

// Model family for the family-aware quant clamp in sampling_gguf.odin.
// .Unset means the profile did not pin it and the id gets sniffed instead.
Quant_Family :: enum {
	Unset,
	Llama,
	Qwen,
}

// Coarse GGUF quant quality tier. .Unset sniffs the tag from the filename.
Quant_Tier :: enum {
	Unset,
	Low,  // Q4 and below, the lossy tier where llama-family drops
	Mid,  // Q5 to Q6
	High, // Q8 and up plus f16/f32
}

Model_Profile :: struct {
	match:                   string, // glob on the model id, eg "qwen*"
	ctx:                     int,    // advertised context window, 0 = unset
	num_ctx:                 int,    // pinned ollama num_ctx, 0 = unset
	temperature:             f64,
	temperature_set:         bool,
	top_p:                   f64,
	top_p_set:               bool,
	reasoning:               Profile_Reasoning,
	one_tool_per_turn:       bool,
	prompt_tier:             Profile_Prompt_Tier,
	parallel_tool_calls:     bool,
	parallel_tool_calls_set: bool,
	// constrained_tools opts the model into server-side output constraints
	// (llama.cpp grammar, ollama/lmstudio json_schema) when tools are sent.
	constrained_tools:       bool,
	constrained_tools_set:   bool,
	// constrained_mode picks the decode constraint strength: strict (full
	// grammar), shape (envelope and key/type locks, free values), or late
	// (constrain only the malformed resample). See tool_constrain_mode.odin.
	constrained_mode:        Constrained_Mode,
	// quant_family / quant_tier override the sniffed model family and GGUF
	// quant tier for the tool-turn temperature clamp (sampling_gguf.odin).
	quant_family:            Quant_Family,
	quant_tier:              Quant_Tier,
	// PA-Tool style per-model renames: canonical tool name -> the alias the
	// request path should advertise. Read-only after load, callers must not
	// free or mutate the map.
	tool_names:              map[string]string,
}

@(private)
g_profiles: []Model_Profile
@(private)
g_profiles_loaded: bool
// Set when the workspace file was skipped for lack of trust so a later
// /hooks trust approval takes effect without a restart.
@(private)
g_profiles_ws_denied: bool
@(private)
g_profiles_mu: sync.Mutex
// Last non-empty model id that went through profile_for. The tools alias
// layer reads it to key per-model renames when a caller cannot pass the
// model explicitly (the agent turn resolves prompt_tier_for_model with the
// request model immediately before building tools JSON).
@(private)
g_last_profile_model: string

/*
Read-only view of the hooks trust store for the workspace
.nullray/model_profiles.json gate. provider cannot import hooks (hooks ->
crash -> rag -> provider would cycle), so the same
<config dir>/hooks_trusted.json records are re-read here. The filename must
stay in sync with hooks.TRUST_STORE_FILE.
*/
@(private)
profile_path_trusted :: proc(path: string) -> bool {
	info, err := os.stat(path, context.temp_allocator)
	if err != nil {
		// Absent file: nothing to load, nothing to gate.
		return true
	}
	if v, ok := os.lookup_env(constants.ENV_HOOKS_TRUST, context.temp_allocator); ok {
		switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
		case "1", "true", "yes", "on":
			return true
		}
	}
	cfg_dir := sandbox.resolve_config_dir(context.temp_allocator)
	store_path, jerr := filepath.join({cfg_dir, "hooks_trusted.json"}, context.temp_allocator)
	if jerr != nil {
		return false
	}
	data, rerr := os.read_entire_file(store_path, context.temp_allocator)
	if rerr != nil {
		return false
	}
	doc, perr := json.parse_string(string(data), .JSON, allocator = context.temp_allocator)
	if perr != nil {
		return false
	}
	root, ok := doc.(json.Object)
	if !ok {
		return false
	}
	files, fok := root["files"].(json.Object)
	if !fok {
		return false
	}
	rec, rok := files[path].(json.Object)
	if !rok {
		return false
	}
	// The store writes mtime_ns/size as quoted decimals: bare numbers parse
	// as f64 here and nanosecond epochs exceed its exact-integer range.
	mtime_ns := profile_json_num(rec["mtime_ns"])
	size := profile_json_num(rec["size"])
	return mtime_ns == time.to_unix_nanoseconds(info.modification_time) && size == i64(info.size)
}

@(private)
profile_json_num :: proc(v: json.Value) -> i64 {
	#partial switch n in v {
	case json.String:
		parsed, ok := strconv.parse_i64(strings.trim_space(string(n)))
		if ok {
			return parsed
		}
	case json.Integer:
		return i64(n)
	case json.Float:
		return i64(n)
	}
	return 0
}

@(private)
profile_workspace_path :: proc(allocator := context.allocator) -> string {
	ws := sandbox.workspace_current()
	if len(ws) == 0 {
		if cwd, cerr := os.get_working_directory(context.temp_allocator); cerr == nil {
			ws = cwd
		}
	}
	if len(ws) == 0 {
		return ""
	}
	p, _ := filepath.join({ws, ".nullray", constants.MODEL_PROFILES_FILE}, allocator)
	return p
}

// Reload the merged profile table from both files. Returns the count loaded.
profile_load :: proc() -> int {
	sync.mutex_lock(&g_profiles_mu)
	defer sync.mutex_unlock(&g_profiles_mu)
	profiles_destroy_locked()
	g_profiles_loaded = true
	list := make([dynamic]Model_Profile, runtime.heap_allocator())
	cfg_dir := sandbox.resolve_config_dir(context.temp_allocator)
	if len(cfg_dir) > 0 {
		if path, err := filepath.join({cfg_dir, constants.MODEL_PROFILES_FILE}, context.temp_allocator); err == nil {
			profile_load_file_into(&list, path)
		}
	}
	ws_path := profile_workspace_path(context.temp_allocator)
	if len(ws_path) > 0 {
		if profile_path_trusted(ws_path) {
			profile_load_file_into(&list, ws_path)
			g_profiles_ws_denied = false
		} else if os.is_file(ws_path) {
			// First sight of a workspace profile table is denied until the
			// operator approves it via /hooks trust, a hostile repo could
			// otherwise force temperature or prompt tier for free.
			g_profiles_ws_denied = true
			fmt.eprintf(
				"nullray: workspace %s not trusted; skipping (approve with /hooks trust)\n",
				ws_path,
			)
		}
	}
	g_profiles = list[:]
	return len(g_profiles)
}

@(private)
profile_ensure_loaded :: proc() {
	sync.mutex_lock(&g_profiles_mu)
	loaded := g_profiles_loaded
	denied := g_profiles_ws_denied
	sync.mutex_unlock(&g_profiles_mu)
	if !loaded {
		profile_load()
		return
	}
	// A denied workspace file becomes loadable the moment it is trusted, so
	// /hooks trust does not need a restart to take effect.
	if denied && profile_path_trusted(profile_workspace_path(context.temp_allocator)) {
		profile_load()
	}
}

@(private)
profile_load_file_into :: proc(list: ^[dynamic]Model_Profile, path: string) {
	data, rerr := os.read_entire_file(path, context.temp_allocator)
	if rerr != nil || len(data) == 0 {
		return
	}
	parsed := profile_parse(string(data), runtime.heap_allocator())
	for p in parsed {
		append(list, p)
	}
	delete(parsed, runtime.heap_allocator())
}

@(private)
profiles_destroy_locked :: proc() {
	for p in g_profiles {
		delete(p.match, runtime.heap_allocator())
		for k, v in p.tool_names {
			delete(k, runtime.heap_allocator())
			delete(v, runtime.heap_allocator())
		}
		delete(p.tool_names)
	}
	delete(g_profiles, runtime.heap_allocator())
	g_profiles = nil
}

/*
Glob match for model ids. * matches any run of characters including
separators (openrouter ids carry provider/model slashes), ? matches exactly
one. Case-insensitive because model tags drift in case across servers.
*/


/*
Apply a matching profile to a request being built. Explicit request fields
(temperature_set / top_p_set / parallel_tool_calls_set / reasoning_effort)
always win over the profile. reasoning off maps to effort "none", on to
"medium", providers that cannot express either just ignore the field.
*/
profile_apply :: proc(provider_id: string, model: string, req: ^Chat_Request) {
	if req == nil {
		return
	}
	_ = provider_id
	prof, ok := profile_for(model)
	if !ok {
		return
	}
	if prof.temperature_set && !req.temperature_set {
		req.temperature = prof.temperature
		req.temperature_set = true
	}
	if prof.top_p_set && !req.top_p_set {
		req.top_p = prof.top_p
		req.top_p_set = true
	}
	if prof.parallel_tool_calls_set && !req.parallel_tool_calls_set {
		req.parallel_tool_calls = prof.parallel_tool_calls
		req.parallel_tool_calls_set = true
	}
	// one_tool_per_turn is the profile shorthand for parallel_tool_calls=0.
	if prof.one_tool_per_turn && !req.parallel_tool_calls_set {
		req.parallel_tool_calls = false
		req.parallel_tool_calls_set = true
	}
	if len(req.reasoning_effort) == 0 {
		switch prof.reasoning {
		case .Off:
			req.reasoning_effort = "none"
		case .On:
			req.reasoning_effort = "medium"
		case .Unset:
		}
	}
}

/*
Emit profile num_ctx for ollama when the env override is absent. Returns
false when the profile has no say, the caller then falls back to
write_ollama_num_ctx_json, where NULLRAY_OLLAMA_NUM_CTX wins outright
(including a <=0 opt-out) and caps-derived values come last.
*/
write_profile_num_ctx_json :: proc(b: ^strings.Builder, model: string) -> bool {
	if _, ok := os.lookup_env(constants.ENV_OLLAMA_NUM_CTX, context.temp_allocator); ok {
		return false
	}
	prof, found := profile_for(model)
	if !found || prof.num_ctx <= 0 {
		return false
	}
	// Braces stay out of sbprintf format strings, fmt treats { as a directive.
	fmt.sbprintf(b, `,"num_ctx":%d`, prof.num_ctx)
	strings.write_string(b, `,"options":{"num_ctx":`)
	fmt.sbprintf(b, `%d`, prof.num_ctx)
	strings.write_byte(b, '}')
	return true
}

// Test hooks: swap the cached table without touching the filesystem.
profile_install_for_test :: proc(json_text: string) {
	sync.mutex_lock(&g_profiles_mu)
	defer sync.mutex_unlock(&g_profiles_mu)
	profiles_destroy_locked()
	g_profiles = profile_parse(json_text, runtime.heap_allocator())
	g_profiles_loaded = true
	if len(g_last_profile_model) > 0 {
		delete(g_last_profile_model, runtime.heap_allocator())
	}
	g_last_profile_model = ""
}

profile_reset_for_test :: proc() {
	sync.mutex_lock(&g_profiles_mu)
	defer sync.mutex_unlock(&g_profiles_mu)
	profiles_destroy_locked()
	g_profiles_loaded = false
	g_profiles_ws_denied = false
	if len(g_last_profile_model) > 0 {
		delete(g_last_profile_model, runtime.heap_allocator())
	}
	g_last_profile_model = ""
}
