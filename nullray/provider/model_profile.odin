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
     "parallel_tool_calls":false}
  ]}

Profiles only fill fields the request did not pin down (the *_set flags on
Chat_Request mark explicit CLI/env values). num_ctx flows through the ollama
write path in openai_compat.odin with NULLRAY_OLLAMA_NUM_CTX still winning
outright, including a <=0 opt-out. JSON parse/serialize live in
model_profile_json.odin.
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
			// operator approves it via /hooks trust; a hostile repo could
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
	}
	delete(g_profiles, runtime.heap_allocator())
	g_profiles = nil
}

/*
Glob match for model ids. * matches any run of characters including
separators (openrouter ids carry provider/model slashes), ? matches exactly
one. Case-insensitive because model tags drift in case across servers.
*/
profile_glob_match :: proc(pattern, model: string) -> bool {
	if len(pattern) == 0 {
		return false
	}
	pat := strings.to_lower(pattern, context.temp_allocator)
	str := strings.to_lower(model, context.temp_allocator)
	p, s := 0, 0
	star_p, star_s := -1, 0
	for s < len(str) {
		if p < len(pat) && (pat[p] == '?' || pat[p] == str[s]) {
			p += 1
			s += 1
		} else if p < len(pat) && pat[p] == '*' {
			star_p = p
			star_s = s
			p += 1
		} else if star_p >= 0 {
			p = star_p + 1
			star_s += 1
			s = star_s
		} else {
			return false
		}
	}
	for p < len(pat) && pat[p] == '*' {
		p += 1
	}
	return p == len(pat)
}

// First matching profile wins; returns ok=false when nothing matches.
profile_for :: proc(model_id: string) -> (Model_Profile, bool) {
	profile_ensure_loaded()
	sync.mutex_lock(&g_profiles_mu)
	defer sync.mutex_unlock(&g_profiles_mu)
	for p in g_profiles {
		if profile_glob_match(p.match, model_id) {
			return p, true
		}
	}
	return {}, false
}

/*
Apply a matching profile to a request being built. Explicit request fields
(temperature_set / top_p_set / parallel_tool_calls_set / reasoning_effort)
always win over the profile. reasoning off maps to effort "none", on to
"medium"; providers that cannot express either just ignore the field.
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
false when the profile has no say; the caller then falls back to
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
	// Braces stay out of sbprintf format strings; fmt treats { as a directive.
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
}

profile_reset_for_test :: proc() {
	sync.mutex_lock(&g_profiles_mu)
	defer sync.mutex_unlock(&g_profiles_mu)
	profiles_destroy_locked()
	g_profiles_loaded = false
	g_profiles_ws_denied = false
}
