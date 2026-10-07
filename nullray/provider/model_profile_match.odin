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
     "parallel_tool_calls":false,"constrained_tools":true}
  ]}

Profiles only fill fields the request did not pin down (the *_set flags on
Chat_Request mark explicit CLI/env values). num_ctx flows through the ollama
write path in openai_compat.odin with NULLRAY_OLLAMA_NUM_CTX still winning
outright, including a <=0 opt-out. JSON parse/serialize live in
model_profile_json.odin.
*/

package provider

import "base:runtime"
import "core:strings"
import "core:sync"

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

// First matching profile wins, returns ok=false when nothing matches.
// Non-empty model ids are remembered in g_last_profile_model so the tools
// alias layer can key per-model renames on the request model even at call
// sites that only know the provider id.
profile_for :: proc(model_id: string) -> (Model_Profile, bool) {
	profile_ensure_loaded()
	sync.mutex_lock(&g_profiles_mu)
	defer sync.mutex_unlock(&g_profiles_mu)
	if len(model_id) > 0 {
		if g_last_profile_model != model_id {
			if len(g_last_profile_model) > 0 {
				delete(g_last_profile_model, runtime.heap_allocator())
			}
			g_last_profile_model = strings.clone(model_id, runtime.heap_allocator())
		}
	}
	for p in g_profiles {
		if profile_glob_match(p.match, model_id) {
			return p, true
		}
	}
	return {}, false
}

// Borrowed view of the last model id recorded by profile_for, "" when none.
// Do not free the result.
profile_last_model :: proc() -> string {
	sync.mutex_lock(&g_profiles_mu)
	defer sync.mutex_unlock(&g_profiles_mu)
	return g_last_profile_model
}