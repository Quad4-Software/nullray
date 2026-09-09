// SPDX-License-Identifier: 0BSD
/*
Embeddings JSON parse tests (offline).
*/

package provider

import "core:strings"
import "core:testing"

@(test)
test_parse_openai_embed_success :: proc(t: ^testing.T) {
	body := `{"model":"m","data":[{"index":0,"embedding":[0.1,0.2,0.3]},{"index":1,"embedding":[0.4,0.5,0.6]}]}`
	res := parse_openai_embed_response(body, context.allocator)
	defer destroy_embed_response(&res)
	testing.expect(t, res.ok)
	testing.expect_value(t, len(res.vectors), 2)
	testing.expect_value(t, len(res.vectors[0]), 3)
	testing.expect(t, res.vectors[0][0] > 0)
}

@(test)
test_parse_openai_embed_reorder :: proc(t: ^testing.T) {
	body := `{"data":[{"index":1,"embedding":[0,1,0]},{"index":0,"embedding":[1,0,0]}]}`
	res := parse_openai_embed_response(body, context.allocator)
	defer destroy_embed_response(&res)
	testing.expect(t, res.ok)
	testing.expect_value(t, res.vectors[0][0], f32(1))
	testing.expect_value(t, res.vectors[1][1], f32(1))
}

@(test)
test_parse_openai_embed_zero_rejected :: proc(t: ^testing.T) {
	body := `{"data":[{"index":0,"embedding":[0,0,0]}]}`
	res := parse_openai_embed_response(body, context.allocator)
	defer destroy_embed_response(&res)
	testing.expect(t, !res.ok)
	testing.expect(t, strings.contains(res.err, "zero"))
}

@(test)
test_parse_openai_embed_empty_data :: proc(t: ^testing.T) {
	body := `{"data":[]}`
	res := parse_openai_embed_response(body, context.allocator)
	defer destroy_embed_response(&res)
	testing.expect(t, !res.ok)
}

@(test)
test_build_openai_embed_body_batch :: proc(t: ^testing.T) {
	body := build_openai_embed_body("m", []string{"a", "b"})
	testing.expect(t, strings.contains(body, `"encoding_format":"float"`))
	testing.expect(t, strings.contains(body, `"a"`))
	testing.expect(t, strings.contains(body, `"b"`))
}

@(test)
test_default_embed_model_ollama :: proc(t: ^testing.T) {
	m := default_embed_model_for_provider("ollama")
	testing.expect_value(t, m, "nomic-embed-text")
}
