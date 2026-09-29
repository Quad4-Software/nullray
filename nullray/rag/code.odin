// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Opt-in semantic index over the live workspace tree. Vector search answers
"where does this concept live" questions that grep cannot, while grep and
subagents keep owning behavioral traces. Off by default: enable with
NULLRAY_RAG_CODE=1, then rag_reindex scope=code.

Chunks carry source="code" so they share the meta.json embed identity with
memory and artifacts. Chunk_Rec.updated stores the file mtime, so query
results can flag files that changed after indexing.
*/

package rag

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:sync"
import "core:time"
import "nullray:constants"
import "nullray:sandbox"

CODE_SOURCE_PREFIX :: "code:"

code_lane_enabled :: proc() -> bool {
	if rag_disabled() {
		return false
	}
	if v, ok := os.lookup_env(constants.ENV_RAG_CODE, context.temp_allocator); ok {
		switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
		case "1", "true", "yes", "on":
			return true
		}
	}
	return false
}

@(private)
Code_File :: struct {
	relpath: string,
	abspath: string,
	mtime:   i64,
	size:    i64,
}

@(private)
code_deny_dir :: proc(name: string) -> bool {
	if len(name) == 0 {
		return true
	}
	if strings.has_prefix(name, ".") {
		return true
	}
	switch name {
	case "node_modules", "vendor", "dist", "build", "out", "target",
	     "__pycache__", "bin", "obj", "coverage", "venv", ".venv":
		return true
	}
	return false
}

@(private)
code_allow_name :: proc(name: string) -> bool {
	switch name {
	case "Makefile", "Dockerfile", "README", "LICENSE", "COPYING",
	     "AGENTS.md", "CLAUDE.md", "Taskfile", "Justfile", "meson.build":
		return true
	}
	if strings.has_prefix(name, "README.") || strings.has_prefix(name, "LICENSE.") {
		return true
	}
	exts := [40]string{
		".odin", ".go", ".py", ".rs", ".ts", ".tsx", ".js", ".jsx",
		".c", ".h", ".cpp", ".hpp", ".cc", ".zig", ".lua", ".vim",
		".java", ".kt", ".swift", ".rb", ".php", ".cs", ".fs", ".scala",
		".clj", ".hs", ".ml", ".nim", ".ex", ".erl", ".dart", ".r", ".jl",
		".md", ".txt", ".toml", ".yaml", ".yml", ".sql", ".sh",
	}
	for ext in exts {
		if strings.has_suffix(name, ext) {
			return true
		}
	}
	return false
}

// Recursive collect with hard caps. Order is depth-first, deterministic
// within a directory listing.
@(private)
code_collect :: proc(root, dir: string, out: ^[dynamic]Code_File, budget: ^i64) {
	if len(out) >= constants.RAG_CODE_MAX_FILES || budget^ <= 0 {
		return
	}
	entries, err := os.read_all_directory_by_path(dir, context.temp_allocator)
	if err != nil {
		return
	}
	for e in entries {
		if len(out) >= constants.RAG_CODE_MAX_FILES || budget^ <= 0 {
			return
		}
		name := e.name
		child, jerr := filepath.join({dir, name}, context.temp_allocator)
		if jerr != nil {
			continue
		}
		if e.type == .Directory {
			if code_deny_dir(name) {
				continue
			}
			code_collect(root, child, out, budget)
			continue
		}
		if e.type != .Regular {
			continue
		}
		if !code_allow_name(name) {
			continue
		}
		if e.size <= 0 || e.size > constants.RAG_CODE_MAX_FILE_BYTES {
			continue
		}
		if e.size > budget^ {
			continue
		}
		budget^ -= e.size
		rel, rerr := filepath.rel(root, child, context.temp_allocator)
		if rerr != nil {
			continue
		}
		mtime := time.to_unix_seconds(e.modification_time)
		append(
			out,
			Code_File{
				relpath = strings.clone(rel, context.temp_allocator),
				abspath = strings.clone(child, context.temp_allocator),
				mtime = mtime,
				size = e.size,
			},
		)
	}
}

@(private)
code_destroy_files :: proc(files: ^[dynamic]Code_File) {
	for f in files {
		delete(f.relpath, context.temp_allocator)
		delete(f.abspath, context.temp_allocator)
	}
	delete(files^)
	files^ = nil
}

// Rebuild every code: chunk in one load-save pass. Returns a summary.
Reindex_Code :: proc(allocator := context.allocator) -> string {
	if !code_lane_enabled() {
		return strings.clone("code lane off (NULLRAY_RAG_CODE=1 to enable)", allocator)
	}
	if !semantic_available() {
		return strings.clone("semantic unavailable (no embed provider)", allocator)
	}
	sync.mutex_lock(&g_ingest_mu)
	defer sync.mutex_unlock(&g_ingest_mu)

	root := workspace_root(context.temp_allocator)
	files := make([dynamic]Code_File, context.temp_allocator)
	defer code_destroy_files(&files)
	budget := i64(constants.RAG_CODE_MAX_TOTAL_BYTES)
	code_collect(root, root, &files, &budget)
	if len(files) == 0 {
		return strings.clone("no indexable files under workspace", allocator)
	}

	prov, model, id_err := current_embed_identity(context.temp_allocator)
	defer delete(prov, context.temp_allocator)
	defer delete(model, context.temp_allocator)
	if len(id_err) > 0 {
		return strings.clone(id_err, allocator)
	}

	chunks, vectors, load_err := load_index(context.allocator)
	defer destroy_chunks(&chunks, context.allocator)
	defer destroy_vector_rows(&vectors, context.allocator)
	meta, mok := load_meta(context.temp_allocator)
	defer if mok {
		delete(meta.embed_provider, context.temp_allocator)
		delete(meta.embed_model, context.temp_allocator)
	}
	if len(load_err) > 0 || (mok && header_mismatch(meta)) {
		// Start fresh rather than mixing dims.
		destroy_chunks(&chunks, context.allocator)
		destroy_vector_rows(&vectors, context.allocator)
		chunks = make([dynamic]Chunk_Rec, context.allocator)
		vectors = make([dynamic][]f32, context.allocator)
		mok = false
	}

	// Drop all prior code chunks.
	kept_c := make([dynamic]Chunk_Rec, context.allocator)
	kept_v := make([dynamic][]f32, context.allocator)
	for c, i in chunks {
		if strings.has_prefix(c.source, CODE_SOURCE_PREFIX) {
			delete(c.id, context.allocator)
			delete(c.source, context.allocator)
			delete(c.key, context.allocator)
			delete(c.text, context.allocator)
			if i < len(vectors) {
				delete(vectors[i], context.allocator)
				vectors[i] = nil
			}
			continue
		}
		append(&kept_c, c)
		if i < len(vectors) {
			append(&kept_v, vectors[i])
			vectors[i] = nil
		}
	}
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

	// Embed in file-sized batches so one bad file does not abort the index.
	dim := 0
	indexed_files := 0
	for f in files {
		if len(chunks) >= constants.RAG_CODE_MAX_CHUNKS {
			break
		}
		body_b, rerr := os.read_entire_file(f.abspath, context.temp_allocator)
		if rerr != nil {
			continue
		}
		body := string(body_b)
		if sandbox.value_looks_secret(body) {
			continue
		}
		headed := fmt.tprintf("%s\n%s", f.relpath, body)
		parts := chunk_text(headed, model, context.temp_allocator)
		if len(parts) == 0 {
			destroy_string_list(&parts, context.temp_allocator)
			continue
		}
		prefixed := make([dynamic]string, context.temp_allocator)
		for p in parts {
			append(&prefixed, prefix_document(model, p, context.temp_allocator))
		}
		src := fmt.tprintf("%s%s", CODE_SOURCE_PREFIX, f.relpath)
		batch := constants.RAG_BATCH
		file_ok := true
		for start := 0; start < len(prefixed); start += batch {
			end := min(start + batch, len(prefixed))
			vecs, eerr := embed_batch(model, prefixed[start:end], context.allocator)
			if len(eerr) > 0 {
				file_ok = false
				break
			}
			for v in vecs {
				if vector_all_zero(v) {
					file_ok = false
				}
			}
			if !file_ok {
				for v in vecs {
					delete(v, context.allocator)
				}
				delete(vecs, context.allocator)
				break
			}
			if len(vecs) != end - start {
				for v in vecs {
					delete(v, context.allocator)
				}
				delete(vecs, context.allocator)
				file_ok = false
				break
			}
			for v, vi in vecs {
				p := parts[start + vi]
				if len(chunks) >= constants.RAG_CODE_MAX_CHUNKS {
					delete(v, context.allocator)
					continue
				}
				append(
					&chunks,
					Chunk_Rec{
						id = strings.clone(fmt.tprintf("%s#%d", src, start + vi), context.allocator),
						source = strings.clone(src, context.allocator),
						key = strings.clone(f.relpath, context.allocator),
						text = strings.clone(p, context.allocator),
						updated = f.mtime,
					},
				)
				append(&vectors, v)
				if dim == 0 {
					dim = len(v)
				}
			}
			delete(vecs, context.allocator)
		}
		destroy_string_list(&parts, context.temp_allocator)
		for s in prefixed {
			delete(s, context.temp_allocator)
		}
		delete(prefixed)
		if file_ok {
			indexed_files += 1
		}
	}
	if dim == 0 && len(vectors) > 0 {
		dim = len(vectors[0])
	}
	created := time.time_to_unix(time.now())
	if mok {
		created = meta.created
	}
	meta_out := Index_Meta{
		version = constants.RAG_INDEX_VERSION,
		embed_provider = strings.clone(prov, context.temp_allocator),
		embed_model = strings.clone(model, context.temp_allocator),
		dim = dim,
		created = created,
	}
	if err := save_index(meta_out, chunks[:], vectors[:]); len(err) > 0 {
		return strings.clone(err, allocator)
	}
	code_chunks := 0
	for c in chunks {
		if strings.has_prefix(c.source, CODE_SOURCE_PREFIX) {
			code_chunks += 1
		}
	}
	return fmt.aprintf(
		"indexed %d files, %d code chunks (dim %d)",
		indexed_files,
		code_chunks,
		dim,
		allocator = allocator,
	)
}
