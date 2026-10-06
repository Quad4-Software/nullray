// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Prefix-cache hygiene tests for build_system_prompt. Providers reuse a warm
KV prefix only while request bytes stay identical, so the prompt must be
byte-stable across rebuilds and volatile sections must sit at the tail.
*/

package agent

import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"
import "core:time"
import "nullray:constants"
import project_memory "nullray:memory"
import "nullray:sandbox"
import "nullray:tools"

@(private)
prompt_cache_ws_begin :: proc(t: ^testing.T) -> (ws: string, prev_ws: string, prev_env: string, had_env: bool) {
	base := "/tmp"
	if td, ok := os.lookup_env("TMPDIR", context.temp_allocator); ok && len(td) > 0 {
		base = td
	}
	ws = fmt.tprintf("%s/nullray-prompt-cache-test-%d", base, time.time_to_unix(time.now()))
	_ = os.remove_all(ws)
	testing.expect(t, os.make_directory_all(ws) == nil)
	st := sandbox.state()
	if st != nil {
		prev_ws = st.workspace
		st.workspace = ws
	}
	prev_env, had_env = os.lookup_env(constants.ENV_WORKSPACE, context.allocator)
	os.set_env(constants.ENV_WORKSPACE, ws)
	return
}

@(private)
prompt_cache_ws_end :: proc(ws, prev_ws, prev_env: string, had_env: bool) {
	st := sandbox.state()
	if st != nil {
		st.workspace = prev_ws
	}
	if had_env {
		os.set_env(constants.ENV_WORKSPACE, prev_env)
		delete(prev_env)
	} else {
		os.unset_env(constants.ENV_WORKSPACE)
	}
	os.remove_all(ws)
}

// Two builds for the same session state must produce identical bytes, even
// across a wall clock boundary. A timestamp or other volatile bytes early in
// the prompt would break this and destroy provider prefix cache hits.
@(test)
test_system_prompt_byte_identical_across_rebuilds :: proc(t: ^testing.T) {
	ws, prev_ws, prev_env, had_env := prompt_cache_ws_begin(t)
	defer prompt_cache_ws_end(ws, prev_ws, prev_env, had_env)

	reg: tools.Registry
	tools.registry_init(&reg)
	defer tools.registry_destroy(&reg)

	p1 := build_system_prompt("skill catalog body", &reg, provider_id = "openai", allocator = context.allocator)
	defer delete(p1)
	time.sleep(1100 * time.Millisecond)
	p2 := build_system_prompt("skill catalog body", &reg, provider_id = "openai", allocator = context.allocator)
	defer delete(p2)
	testing.expect_value(t, p1, p2)
}

// Stable sections must come before volatile ones so a per-turn RAG block or
// a memory write does not invalidate the cached prefix in front of them.
// Expected tail order: skills catalog (stable), project memory digest
// (write-time volatile), retrieved memory (per-turn volatile).
@(test)
test_system_prompt_tail_orders_stable_first :: proc(t: ^testing.T) {
	ws, prev_ws, prev_env, had_env := prompt_cache_ws_begin(t)
	defer prompt_cache_ws_end(ws, prev_ws, prev_env, had_env)

	prev_prompt, had_prompt := os.lookup_env(constants.ENV_PROMPT, context.allocator)
	os.set_env(constants.ENV_PROMPT, "full")
	defer {
		if had_prompt {
			os.set_env(constants.ENV_PROMPT, prev_prompt)
			delete(prev_prompt)
		} else {
			os.unset_env(constants.ENV_PROMPT)
		}
	}

	put_msg, put_err := project_memory.Put("build.verify", "make test")
	defer delete(put_msg)
	defer delete(put_err)
	testing.expect_value(t, put_err, "")

	reg: tools.Registry
	tools.registry_init(&reg)
	defer tools.registry_destroy(&reg)

	p := build_system_prompt("skill catalog body", &reg, provider_id = "openai", allocator = context.allocator)
	defer delete(p)

	skills_i := strings.index(p, "## Skills catalog")
	mem_i := strings.index(p, "## Project memory")
	rag_i := strings.index(p, "## Retrieved memory")
	testing.expect(t, skills_i >= 0)
	testing.expect(t, mem_i >= 0)
	testing.expect(t, skills_i < mem_i)
	if rag_i >= 0 {
		testing.expect(t, mem_i < rag_i)
	}
}
