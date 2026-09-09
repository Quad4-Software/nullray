// SPDX-License-Identifier: 0BSD
/*
Cosine query and hybrid lexical merge.
*/

package rag

import "core:fmt"
import "core:math"
import "core:slice"
import "core:strings"
import "nullray:constants"
import project_memory "nullray:memory"

Scored_Idx :: struct {
	idx:   int,
	score: f32,
}

Hybrid_Merged :: struct {
	key:    string,
	text:   string,
	source: string,
	score:  f32,
}

cosine :: proc(a, b: []f32) -> f32 {
	if len(a) == 0 || len(a) != len(b) {
		return 0
	}
	dot: f32 = 0
	na: f32 = 0
	nb: f32 = 0
	for i in 0 ..< len(a) {
		dot += a[i] * b[i]
		na += a[i] * a[i]
		nb += b[i] * b[i]
	}
	if na <= 0 || nb <= 0 {
		return 0
	}
	return dot / (math.sqrt(na) * math.sqrt(nb))
}

Query :: proc(q: string, top_k: int = constants.RAG_TOP_K, allocator := context.allocator) -> (
	hits: [dynamic]Hit,
	err: string,
) {
	hits = make([dynamic]Hit, allocator)
	if rag_disabled() {
		return hits, ""
	}
	needle := strings.trim_space(q)
	if len(needle) == 0 {
		return hits, ""
	}
	if !semantic_available() {
		return hits, strings.clone("semantic unavailable", allocator)
	}
	meta, mok := load_meta(context.temp_allocator)
	defer if mok {
		delete(meta.embed_provider, context.temp_allocator)
		delete(meta.embed_model, context.temp_allocator)
	}
	if mok && header_mismatch(meta) {
		return hits, strings.clone("rag index stale (embed model changed) run rag_reindex", allocator)
	}
	chunks, vectors, load_err := load_index(context.temp_allocator)
	defer destroy_chunks(&chunks, context.temp_allocator)
	defer destroy_vector_rows(&vectors, context.temp_allocator)
	if len(load_err) > 0 {
		return hits, strings.clone(load_err, allocator)
	}
	if len(chunks) == 0 {
		return hits, ""
	}
	prov, model, id_err := current_embed_identity(context.temp_allocator)
	_ = prov
	defer delete(prov, context.temp_allocator)
	defer delete(model, context.temp_allocator)
	if len(id_err) > 0 {
		return hits, strings.clone(id_err, allocator)
	}
	pref := prefix_query(model, needle, context.temp_allocator)
	defer delete(pref, context.temp_allocator)
	vecs, eerr := embed_batch(model, []string{pref}, context.allocator)
	if len(eerr) > 0 {
		return hits, strings.clone(eerr, allocator)
	}
	defer {
		for v in vecs {
			delete(v, context.allocator)
		}
		delete(vecs, context.allocator)
	}
	if len(vecs) == 0 {
		return hits, strings.clone("empty query embedding", allocator)
	}
	qvec := vecs[0]
	scored := make([dynamic]Scored_Idx, context.temp_allocator)
	for i in 0 ..< len(chunks) {
		if i >= len(vectors) {
			break
		}
		s := cosine(qvec, vectors[i])
		if s < f32(constants.RAG_MIN_SCORE) {
			continue
		}
		append(&scored, Scored_Idx{idx = i, score = s})
	}
	slice.sort_by(scored[:], proc(a, b: Scored_Idx) -> bool {
		return a.score > b.score
	})
	k := top_k
	if k <= 0 {
		k = constants.RAG_TOP_K
	}
	if k > len(scored) {
		k = len(scored)
	}
	for i in 0 ..< k {
		c := chunks[scored[i].idx]
		append(
			&hits,
			Hit{
				source = strings.clone(c.source, allocator),
				key = strings.clone(c.key, allocator),
				text = strings.clone(c.text, allocator),
				score = scored[i].score,
			},
		)
	}
	return hits, ""
}

Lexical_Hit :: struct {
	key:       string,
	value:     string,
	key_match: bool,
}

Hybrid_Search :: proc(
	q: string,
	lexical: []Lexical_Hit,
	top_k: int = constants.RAG_TOP_K,
	allocator := context.allocator,
) -> (
	hits: [dynamic]Hit,
	note: string,
) {
	hits = make([dynamic]Hit, allocator)
	sem, serr := Query(q, top_k * 2, context.temp_allocator)
	defer destroy_hits(&sem, context.temp_allocator)
	if len(serr) > 0 {
		note = strings.clone(fmt.tprintf("semantic unavailable: %s", serr), allocator)
	}
	alpha := f32(constants.RAG_HYBRID_ALPHA)
	merged := make([dynamic]Hybrid_Merged, context.temp_allocator)
	seen := make(map[string]int, context.temp_allocator)

	for h, i in lexical {
		lex: f32 = 0.35
		if h.key_match {
			lex = 0.55
		}
		score := (1 - alpha) * lex
		append(
			&merged,
			Hybrid_Merged{
				key = h.key,
				text = h.value,
				source = "memory",
				score = score,
			},
		)
		seen[h.key] = len(merged) - 1
		_ = i
	}
	for h in sem {
		key := h.key
		if len(key) == 0 {
			key = h.source
		}
		if idx, ok := seen[key]; ok {
			merged[idx].score = alpha * h.score + (1 - alpha) * merged[idx].score
			if len(h.text) > len(merged[idx].text) {
				merged[idx].text = h.text
			}
		} else {
			append(
				&merged,
				Hybrid_Merged{
					key = key,
					text = h.text,
					source = h.source,
					score = alpha * h.score,
				},
			)
			seen[key] = len(merged) - 1
		}
	}
	slice.sort_by(merged[:], proc(a, b: Hybrid_Merged) -> bool {
		return a.score > b.score
	})
	k := top_k
	if k <= 0 {
		k = constants.RAG_TOP_K
	}
	if k > len(merged) {
		k = len(merged)
	}
	for i in 0 ..< k {
		m := merged[i]
		append(
			&hits,
			Hit{
				source = strings.clone(m.source, allocator),
				key = strings.clone(m.key, allocator),
				text = strings.clone(m.text, allocator),
				score = m.score,
			},
		)
	}
	return hits, note
}

Prompt_Block :: proc(q: string, max_chars: int = constants.RAG_PROMPT_CHARS, allocator := context.allocator) -> string {
	if rag_disabled() || len(strings.trim_space(q)) == 0 {
		return ""
	}
	hits, err := Query(q, constants.RAG_TOP_K, context.temp_allocator)
	defer destroy_hits(&hits, context.temp_allocator)
	if len(err) > 0 {
		defer delete(err, context.temp_allocator)
		if rag_forced() {
			return fmt.aprintf("(rag retrieve failed: %s)\n", err, allocator = allocator)
		}
		return ""
	}
	if len(hits) == 0 {
		return ""
	}
	b: strings.Builder
	strings.builder_init(&b, allocator)
	used := 0
	for h in hits {
		line := fmt.tprintf("- [%s] %s\n", h.key, project_memory.one_line_summary(h.text, 240, context.temp_allocator))
		if used + len(line) > max_chars {
			break
		}
		strings.write_string(&b, line)
		used += len(line)
	}
	return strings.to_string(b)
}
