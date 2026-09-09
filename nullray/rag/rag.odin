// SPDX-License-Identifier: 0BSD
/*
In-harness RAG: env gates, paths, and public types.
*/

package rag

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "nullray:constants"
import "nullray:provider"
import "nullray:sandbox"

Hit :: struct {
	source: string,
	key:    string,
	text:   string,
	score:  f32,
}

Index_Meta :: struct {
	version:        int,
	embed_provider: string,
	embed_model:    string,
	dim:            int,
	created:        i64,
	stale:          bool,
}

Chunk_Rec :: struct {
	id:      string,
	source:  string,
	key:     string,
	text:    string,
	updated: i64,
}

g_embed_override: proc(model: string, inputs: []string, allocator := context.allocator) -> ([][]f32, string)
g_provider_reg: ^provider.Registry
g_chat_provider: ^provider.Provider

set_embed_override :: proc(
	fn: proc(model: string, inputs: []string, allocator := context.allocator) -> ([][]f32, string),
) {
	g_embed_override = fn
}

bind_providers :: proc(reg: ^provider.Registry, chat: ^provider.Provider) {
	g_provider_reg = reg
	g_chat_provider = chat
}

rag_mode :: proc() -> string {
	if v, ok := os.lookup_env(constants.ENV_RAG, context.temp_allocator); ok {
		return strings.to_lower(strings.trim_space(v), context.temp_allocator)
	}
	return "auto"
}

rag_disabled :: proc() -> bool {
	switch rag_mode() {
	case "0", "false", "no", "off", "disable", "disabled":
		return true
	}
	return false
}

rag_forced :: proc() -> bool {
	switch rag_mode() {
	case "1", "true", "yes", "on", "force", "forced":
		return true
	}
	return false
}

artifacts_enabled :: proc() -> bool {
	if rag_disabled() {
		return false
	}
	if v, ok := os.lookup_env(constants.ENV_RAG_ARTIFACTS, context.temp_allocator); ok {
		switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
		case "0", "false", "no", "off", "disable", "disabled":
			return false
		}
	}
	return true
}

workspace_root :: proc(allocator := context.allocator) -> string {
	st := sandbox.state()
	if st != nil && len(st.workspace) > 0 {
		return strings.clone(st.workspace, allocator)
	}
	if v, ok := os.lookup_env(constants.ENV_WORKSPACE, context.temp_allocator); ok && len(v) > 0 {
		return strings.clone(v, allocator)
	}
	if cwd, err := os.get_working_directory(allocator); err == nil {
		return cwd
	}
	return strings.clone(".", allocator)
}

rag_dir :: proc(allocator := context.allocator) -> string {
	root := workspace_root(context.temp_allocator)
	path, err := filepath.join({root, constants.RAG_DIR}, allocator)
	if err != nil {
		return strings.clone(constants.RAG_DIR, allocator)
	}
	return path
}

meta_path :: proc(allocator := context.allocator) -> string {
	dir := rag_dir(context.temp_allocator)
	path, err := filepath.join({dir, "meta.json"}, allocator)
	if err != nil {
		return strings.clone("meta.json", allocator)
	}
	return path
}

chunks_path :: proc(allocator := context.allocator) -> string {
	dir := rag_dir(context.temp_allocator)
	path, err := filepath.join({dir, "chunks.jsonl"}, allocator)
	if err != nil {
		return strings.clone("chunks.jsonl", allocator)
	}
	return path
}

vectors_path :: proc(allocator := context.allocator) -> string {
	dir := rag_dir(context.temp_allocator)
	path, err := filepath.join({dir, "vectors.bin"}, allocator)
	if err != nil {
		return strings.clone("vectors.bin", allocator)
	}
	return path
}

ensure_rag_dir :: proc() -> string {
	dir := rag_dir(context.temp_allocator)
	if err := os.make_directory_all(dir); err != nil && err != .Exist {
		return fmt.tprintf("rag mkdir failed: %v", err)
	}
	return ""
}

destroy_hits :: proc(hits: ^[dynamic]Hit, allocator := context.allocator) {
	if hits == nil {
		return
	}
	for h in hits {
		delete(h.source, allocator)
		delete(h.key, allocator)
		delete(h.text, allocator)
	}
	delete(hits^)
	hits^ = nil
}

destroy_chunks :: proc(chunks: ^[dynamic]Chunk_Rec, allocator := context.allocator) {
	if chunks == nil {
		return
	}
	for c in chunks {
		delete(c.id, allocator)
		delete(c.source, allocator)
		delete(c.key, allocator)
		delete(c.text, allocator)
	}
	delete(chunks^)
	chunks^ = nil
}

Status :: proc(allocator := context.allocator) -> string {
	mode := rag_mode()
	meta, mok := load_meta(context.temp_allocator)
	defer if mok {
		delete(meta.embed_provider, context.temp_allocator)
		delete(meta.embed_model, context.temp_allocator)
	}
	chunks, vectors, load_err := load_index(context.temp_allocator)
	defer destroy_chunks(&chunks, context.temp_allocator)
	defer destroy_vector_rows(&vectors, context.temp_allocator)
	n := len(chunks)
	dim := 0
	stale := false
	if mok {
		dim = meta.dim
		stale = meta.stale || header_mismatch(meta)
	}
	err_note := load_err
	model := ""
	prov := ""
	if mok {
		model = meta.embed_model
		prov = meta.embed_provider
	} else {
		ep, owned, _ := provider.resolve_embed_provider(g_provider_reg, g_chat_provider, context.temp_allocator)
		if ep != nil {
			prov = ep.id
			model = provider.resolve_embed_model(ep)
			if owned {
				provider.provider_destroy(ep)
				free(ep)
			}
		}
	}
	return fmt.aprintf(
		"rag mode=%s chunks=%d dim=%d provider=%s model=%s stale=%v %s",
		mode,
		n,
		dim,
		prov,
		model,
		stale,
		err_note,
		allocator = allocator,
	)
}
