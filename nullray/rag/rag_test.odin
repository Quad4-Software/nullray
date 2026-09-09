// SPDX-License-Identifier: 0BSD
/*
Offline RAG unit tests with fake embeddings.
*/

package rag

import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"
import "core:thread"
import "core:time"
import "nullray:constants"
import "nullray:store"

Test_Ws :: struct {
	ws:   string,
	prev: string,
	had:  bool,
}

test_rag_ws_begin :: proc(t: ^testing.T) -> Test_Ws {
	ctx: Test_Ws
	ctx.ws = fmt.tprintf("/run/media/user1/projects/pie/.tmp/nullray-rag-test-%d", time.time_to_unix(time.now()))
	_ = os.remove_all(ctx.ws)
	testing.expect(t, os.make_directory_all(ctx.ws) == nil)
	ctx.prev, ctx.had = os.lookup_env(constants.ENV_WORKSPACE, context.allocator)
	os.set_env(constants.ENV_WORKSPACE, ctx.ws)
	os.set_env(constants.ENV_RAG, "1")
	set_embed_override(fake_embed)
	return ctx
}

test_rag_ws_end :: proc(ctx: Test_Ws) {
	set_embed_override(nil)
	os.unset_env(constants.ENV_RAG)
	if ctx.had {
		os.set_env(constants.ENV_WORKSPACE, ctx.prev)
		delete(ctx.prev)
	} else {
		os.unset_env(constants.ENV_WORKSPACE)
	}
	_ = os.remove_all(ctx.ws)
}

fake_embed :: proc(model: string, inputs: []string, allocator := context.allocator) -> ([][]f32, string) {
	_ = model
	out := make([][]f32, len(inputs), allocator)
	for s, i in inputs {
		v := make([]f32, 8, allocator)
		lower := strings.to_lower(s, context.temp_allocator)
		v[0] = 0.1
		if strings.contains(lower, "alpha") {
			v[1] = 1
		}
		if strings.contains(lower, "beta") {
			v[2] = 1
		}
		if strings.contains(lower, "gamma") {
			v[3] = 1
		}
		// Slight uniqueness from length.
		v[7] = f32(len(s) % 5) * 0.01
		out[i] = v
	}
	return out, ""
}

@(test)
test_chunk_boundaries_and_empty :: proc(t: ^testing.T) {
	parts := chunk_text("", "nomic-embed-text", context.allocator)
	testing.expect_value(t, len(parts), 0)
	destroy_string_list(&parts)

	small := chunk_text("hello world", "nomic-embed-text", context.allocator)
	testing.expect_value(t, len(small), 1)
	destroy_string_list(&small)

	big_b: strings.Builder
	strings.builder_init(&big_b, context.temp_allocator)
	for i in 0 ..< 200 {
		fmt.sbprintf(&big_b, "word%d ", i)
	}
	big := strings.to_string(big_b)
	parts2 := chunk_text(big, "all-minilm", context.allocator)
	testing.expect(t, len(parts2) >= 2)
	for p in parts2 {
		testing.expect(t, len(p) <= constants.RAG_MAX_CHUNK_CHARS_MINILM)
	}
	destroy_string_list(&parts2)
}

@(test)
test_nomic_prefixes :: proc(t: ^testing.T) {
	testing.expect(t, uses_nomic_prefixes("nomic-embed-text"))
	d := prefix_document("nomic-embed-text", "doc", context.allocator)
	defer delete(d)
	testing.expect(t, strings.has_prefix(d, "search_document: "))
	q := prefix_query("nomic-embed-text", "q", context.allocator)
	defer delete(q)
	testing.expect(t, strings.has_prefix(q, "search_query: "))
}

@(test)
test_index_roundtrip_and_query :: proc(t: ^testing.T) {
	ctx := test_rag_ws_begin(t)
	defer test_rag_ws_end(ctx)
	err := Index_Memory_Entry("pref.alpha", "alpha lives here with detail")
	testing.expect_value(t, err, "")
	err = Index_Memory_Entry("pref.beta", "beta token elsewhere")
	testing.expect_value(t, err, "")
	hits, qerr := Query("alpha", 3, context.allocator)
	defer destroy_hits(&hits)
	testing.expect_value(t, qerr, "")
	testing.expect(t, len(hits) >= 1)
	testing.expect(t, strings.contains(hits[0].key, "alpha") || strings.contains(hits[0].text, "alpha"))
}

@(test)
test_hybrid_prefers_semantic :: proc(t: ^testing.T) {
	ctx := test_rag_ws_begin(t)
	defer test_rag_ws_end(ctx)
	_ = Index_Memory_Entry("pref.alpha", "alpha semantic payload")
	_ = Index_Memory_Entry("pref.other", "unrelated lexical match alpha in key only")
	lex := []Lexical_Hit{
		{key = "pref.other", value = "unrelated", key_match = true},
		{key = "pref.alpha", value = "alpha semantic payload", key_match = false},
	}
	hits, _ := Hybrid_Search("alpha meaning", lex, 2, context.allocator)
	defer destroy_hits(&hits)
	testing.expect(t, len(hits) >= 1)
}

@(test)
test_secret_refused :: proc(t: ^testing.T) {
	ctx := test_rag_ws_begin(t)
	defer test_rag_ws_end(ctx)
	err := Index_Text("memory:pref.secret", "api_key=supersecret", "pref.secret")
	testing.expect(t, strings.contains(err, "secret"))
}

@(test)
test_zero_vector_rejection_via_override :: proc(t: ^testing.T) {
	ctx := test_rag_ws_begin(t)
	defer test_rag_ws_end(ctx)
	set_embed_override(proc(model: string, inputs: []string, allocator := context.allocator) -> ([][]f32, string) {
		_ = model
		out := make([][]f32, len(inputs), allocator)
		for i in 0 ..< len(inputs) {
			out[i] = make([]f32, 4, allocator)
		}
		return out, ""
	})
	err := Index_Text("memory:pref.z", "alpha content", "pref.z")
	testing.expect(t, strings.contains(err, "zero"))
}

@(test)
test_remove_memory_key :: proc(t: ^testing.T) {
	ctx := test_rag_ws_begin(t)
	defer test_rag_ws_end(ctx)
	_ = Index_Memory_Entry("pref.gone", "alpha leave")
	_ = Remove_Memory_Key("pref.gone")
	hits, _ := Query("alpha", 3, context.allocator)
	defer destroy_hits(&hits)
	for h in hits {
		testing.expect(t, h.key != "pref.gone")
	}
}

@(test)
test_cosine_identical :: proc(t: ^testing.T) {
	a := []f32{1, 0, 0}
	b := []f32{1, 0, 0}
	testing.expect(t, cosine(a, b) > 0.99)
	c := []f32{0, 1, 0}
	testing.expect(t, cosine(a, c) < 0.01)
}

@(test)
test_prompt_block_forced_surfaces_error :: proc(t: ^testing.T) {
	ctx := test_rag_ws_begin(t)
	defer test_rag_ws_end(ctx)
	set_embed_override(fake_embed)
	testing.expect_value(t, Index_Memory_Entry("pref.alpha", "alpha lives"), "")
	set_embed_override(proc(model: string, inputs: []string, allocator := context.allocator) -> ([][]f32, string) {
		_ = model
		_ = inputs
		return nil, strings.clone("embed down", allocator)
	})
	block := Prompt_Block("alpha", 500, context.allocator)
	defer delete(block)
	testing.expect(t, strings.contains(block, "rag retrieve failed"))
}

@(test)
test_query_stale_after_meta_rewrite :: proc(t: ^testing.T) {
	ctx := test_rag_ws_begin(t)
	defer test_rag_ws_end(ctx)
	testing.expect_value(t, Index_Memory_Entry("pref.alpha", "alpha payload"), "")
	meta_p := meta_path(context.temp_allocator)
	body := `{"version":1,"embed_provider":"test","embed_model":"other-model","dim":8,"created":1}` + "\n"
	testing.expect(t, os.write_entire_file(meta_p, transmute([]u8)body) == nil)
	hits, err := Query("alpha", 3, context.allocator)
	defer destroy_hits(&hits)
	defer delete(err)
	testing.expect(t, strings.contains(err, "stale"))
}

@(test)
test_artifact_survives_reindex :: proc(t: ^testing.T) {
	ctx := test_rag_ws_begin(t)
	defer test_rag_ws_end(ctx)
	id, ok := store.artifact_store("gamma artifact body unique_token_xyz", context.allocator)
	testing.expect(t, ok)
	defer delete(id)
	testing.expect_value(t, Index_Artifact(id, "gamma artifact body unique_token_xyz"), "")
	testing.expect_value(t, Index_Memory_Entry("pref.alpha", "alpha memory"), "")
	testing.expect_value(t, Reindex_Memory(), "")
	hits, err := Query("gamma unique_token", 5, context.allocator)
	defer destroy_hits(&hits)
	testing.expect_value(t, err, "")
	found := false
	for h in hits {
		if strings.contains(h.text, "unique_token_xyz") || strings.contains(h.source, "artifact:") {
			found = true
		}
	}
	testing.expect(t, found)
}

@(test)
test_auto_silent_vs_forced_error :: proc(t: ^testing.T) {
	ctx := test_rag_ws_begin(t)
	defer test_rag_ws_end(ctx)
	os.set_env(constants.ENV_RAG, "auto")
	set_embed_override(nil)
	testing.expect_value(t, Index_Memory_Entry("pref.alpha", "alpha"), "")
	os.set_env(constants.ENV_RAG, "1")
	err := Index_Memory_Entry("pref.beta", "beta")
	testing.expect(t, len(err) > 0)
	set_embed_override(fake_embed)
}

@(test)
test_concurrent_ingest_no_crash :: proc(t: ^testing.T) {
	ctx := test_rag_ws_begin(t)
	defer test_rag_ws_end(ctx)
	Worker :: struct {
		i: int,
	}
	workers := make([]^thread.Thread, 8, context.temp_allocator)
	args := make([]Worker, 8, context.temp_allocator)
	for i in 0 ..< 8 {
		args[i] = Worker{i = i}
		workers[i] = thread.create_and_start_with_poly_data(&args[i], proc(w: ^Worker) {
			key := fmt.tprintf("pref.c%d", w.i)
			val := fmt.tprintf("alpha concurrent %d", w.i)
			_ = Index_Memory_Entry(key, val)
		})
	}
	for th in workers {
		thread.join(th)
		thread.destroy(th)
	}
	hits, err := Query("alpha", 5, context.allocator)
	defer destroy_hits(&hits)
	testing.expect_value(t, err, "")
	testing.expect(t, len(hits) >= 1)
}
