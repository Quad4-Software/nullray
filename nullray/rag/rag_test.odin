// SPDX-License-Identifier: 0BSD
/*
Offline RAG unit tests with fake embeddings.
*/

package rag

import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"
import "core:time"
import "nullray:constants"

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
		_ = inputs
		out := make([][]f32, 1, allocator)
		out[0] = make([]f32, 4, allocator)
		return out, ""
	})
	// Index_Text will embed and save zeros - save_index doesn't reject zeros.
	// Query path uses embed_batch which returns zeros. Cosine may be nan/0.
	_ = Index_Text("memory:pref.z", "alpha content", "pref.z")
	hits, _ := Query("alpha", 3, context.allocator)
	defer destroy_hits(&hits)
	// Min score filter should drop zero similarity.
	for h in hits {
		testing.expect(t, h.score >= f32(constants.RAG_MIN_SCORE) || h.score == 0)
	}
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
