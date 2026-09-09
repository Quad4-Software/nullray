// SPDX-License-Identifier: 0BSD
/*
Index memory entries and free-form text into the RAG store.
*/

package rag

import "core:fmt"
import "core:strings"
import "core:time"
import "nullray:constants"
import project_memory "nullray:memory"
import "nullray:sandbox"

source_memory :: proc(key: string, allocator := context.allocator) -> string {
	return fmt.aprintf("memory:%s", key, allocator = allocator)
}

Index_Memory_Entry :: proc(key, value: string) -> string {
	if rag_disabled() {
		return ""
	}
	if !semantic_available() {
		if rag_forced() {
			return "semantic unavailable"
		}
		return ""
	}
	trimmed_key := strings.trim_space(key)
	if len(trimmed_key) == 0 || len(strings.trim_space(value)) == 0 {
		return ""
	}
	if sandbox.value_looks_secret(value) {
		return "refusing to index secret-shaped text"
	}
	src := source_memory(trimmed_key, context.temp_allocator)
	return Index_Text(src, value, trimmed_key)
}

Index_Text :: proc(source_id, text, key: string) -> string {
	if rag_disabled() {
		return ""
	}
	if !semantic_available() {
		if rag_forced() {
			return "semantic unavailable"
		}
		return ""
	}
	body := strings.trim_space(text)
	if len(body) == 0 {
		return ""
	}
	if sandbox.value_looks_secret(body) {
		return "refusing to index secret-shaped text"
	}
	if len(body) > constants.RAG_ARTIFACT_MAX_CHARS {
		body = body[:constants.RAG_ARTIFACT_MAX_CHARS]
	}
	prov, model, id_err := current_embed_identity(context.temp_allocator)
	defer delete(prov, context.temp_allocator)
	defer delete(model, context.temp_allocator)
	if len(id_err) > 0 {
		return id_err
	}

	meta, mok := load_meta(context.temp_allocator)
	defer if mok {
		delete(meta.embed_provider, context.temp_allocator)
		delete(meta.embed_model, context.temp_allocator)
	}
	if mok && header_mismatch(meta) {
		_ = Clear()
		mok = false
	}

	chunks, vectors, load_err := load_index(context.allocator)
	defer destroy_chunks(&chunks, context.allocator)
	defer destroy_vector_rows(&vectors, context.allocator)
	if len(load_err) > 0 && mok {
		_ = Clear()
		destroy_chunks(&chunks, context.allocator)
		destroy_vector_rows(&vectors, context.allocator)
		chunks = make([dynamic]Chunk_Rec, context.allocator)
		vectors = make([dynamic][]f32, context.allocator)
	}

	// Drop existing chunks for this source.
	kept_c := make([dynamic]Chunk_Rec, context.allocator)
	kept_v := make([dynamic][]f32, context.allocator)
	for c, i in chunks {
		if c.source == source_id {
			continue
		}
		append(&kept_c, c)
		if i < len(vectors) {
			append(&kept_v, vectors[i])
			vectors[i] = nil
		}
	}
	// Prevent double-free of moved rows.
	for i in 0 ..< len(chunks) {
		chunks[i] = {}
	}
	for i in 0 ..< len(vectors) {
		vectors[i] = nil
	}
	destroy_chunks(&chunks, context.allocator)
	destroy_vector_rows(&vectors, context.allocator)
	chunks = kept_c
	vectors = kept_v

	parts := chunk_text(body, model, context.temp_allocator)
	defer destroy_string_list(&parts, context.temp_allocator)
	if len(parts) == 0 {
		dim0 := 0
		created0 := time.time_to_unix(time.now())
		if mok {
			dim0 = meta.dim
			created0 = meta.created
		}
		if dim0 == 0 && len(vectors) > 0 {
			dim0 = len(vectors[0])
		}
		meta_out := Index_Meta{
			version = constants.RAG_INDEX_VERSION,
			embed_provider = strings.clone(prov, context.temp_allocator),
			embed_model = strings.clone(model, context.temp_allocator),
			dim = dim0,
			created = created0,
		}
		return save_index(meta_out, chunks[:], vectors[:])
	}

	prefixed := make([dynamic]string, context.temp_allocator)
	for p in parts {
		append(&prefixed, prefix_document(model, p, context.temp_allocator))
	}
	defer for s in prefixed {
		delete(s, context.temp_allocator)
	}

	batch := constants.RAG_BATCH
	new_vecs := make([dynamic][]f32, context.allocator)
	for start := 0; start < len(prefixed); start += batch {
		end := start + batch
		if end > len(prefixed) {
			end = len(prefixed)
		}
		batch_in := prefixed[start:end]
		vecs, eerr := embed_batch(model, batch_in[:], context.allocator)
		if len(eerr) > 0 {
			destroy_vector_rows(&new_vecs, context.allocator)
			return eerr
		}
		for v in vecs {
			append(&new_vecs, v)
		}
		delete(vecs, context.allocator)
	}
	if len(new_vecs) != len(parts) {
		destroy_vector_rows(&new_vecs, context.allocator)
		return "embed batch size mismatch"
	}
	dim := len(new_vecs[0])
	now := time.time_to_unix(time.now())
	for p, i in parts {
		id := fmt.aprintf("%s#%d", source_id, i, allocator = context.allocator)
		append(
			&chunks,
			Chunk_Rec{
				id = id,
				source = strings.clone(source_id, context.allocator),
				key = strings.clone(key, context.allocator),
				text = strings.clone(p, context.allocator),
				updated = now,
			},
		)
		append(&vectors, new_vecs[i])
		new_vecs[i] = nil
	}
	destroy_vector_rows(&new_vecs, context.allocator)

	created1 := now
	if mok {
		created1 = meta.created
	}
	meta_out := Index_Meta{
		version = constants.RAG_INDEX_VERSION,
		embed_provider = strings.clone(prov, context.temp_allocator),
		embed_model = strings.clone(model, context.temp_allocator),
		dim = dim,
		created = created1,
	}
	return save_index(meta_out, chunks[:], vectors[:])
}

Remove :: proc(source_id: string) -> string {
	chunks, vectors, load_err := load_index(context.allocator)
	defer destroy_chunks(&chunks, context.allocator)
	defer destroy_vector_rows(&vectors, context.allocator)
	if len(load_err) > 0 {
		return load_err
	}
	meta, mok := load_meta(context.temp_allocator)
	defer if mok {
		delete(meta.embed_provider, context.temp_allocator)
		delete(meta.embed_model, context.temp_allocator)
	}
	kept_c := make([dynamic]Chunk_Rec, context.allocator)
	kept_v := make([dynamic][]f32, context.allocator)
	for c, i in chunks {
		if c.source == source_id || strings.has_prefix(c.source, source_id) {
			delete(c.id, context.allocator)
			delete(c.source, context.allocator)
			delete(c.key, context.allocator)
			delete(c.text, context.allocator)
			if i < len(vectors) {
				delete(vectors[i], context.allocator)
				vectors[i] = nil
			}
			chunks[i] = {}
			continue
		}
		append(&kept_c, c)
		if i < len(vectors) {
			append(&kept_v, vectors[i])
			vectors[i] = nil
		}
		chunks[i] = {}
	}
	destroy_chunks(&chunks, context.allocator)
	destroy_vector_rows(&vectors, context.allocator)
	if !mok {
		_ = Clear()
		destroy_chunks(&kept_c, context.allocator)
		destroy_vector_rows(&kept_v, context.allocator)
		return ""
	}
	err := save_index(meta, kept_c[:], kept_v[:])
	destroy_chunks(&kept_c, context.allocator)
	destroy_vector_rows(&kept_v, context.allocator)
	return err
}

Remove_Memory_Key :: proc(key: string) -> string {
	src := source_memory(strings.trim_space(key), context.temp_allocator)
	return Remove(src)
}

Reindex_Memory :: proc() -> string {
	if rag_disabled() {
		return "rag disabled"
	}
	if !semantic_available() {
		return "semantic unavailable"
	}
	_ = Clear()
	entries := project_memory.load_entries(context.temp_allocator)
	defer project_memory.destroy_entries(&entries, context.temp_allocator)
	for e in entries {
		if err := Index_Memory_Entry(e.key, e.value); len(err) > 0 {
			return err
		}
	}
	return ""
}

Index_Artifact :: proc(id, body: string) -> string {
	if !artifacts_enabled() {
		return ""
	}
	if len(body) == 0 || len(body) > constants.RAG_ARTIFACT_MAX_CHARS {
		return ""
	}
	redacted := sandbox.redact_secrets(body, context.temp_allocator)
	src := fmt.tprintf("artifact:%s", id)
	return Index_Text(src, redacted, id)
}
