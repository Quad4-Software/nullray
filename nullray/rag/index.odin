// SPDX-License-Identifier: 0BSD
/*
On-disk RAG index: meta.json, chunks.jsonl, vectors.bin.
*/

package rag

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import "nullray:constants"

destroy_vector_rows :: proc(rows: ^[dynamic][]f32, allocator := context.allocator) {
	if rows == nil {
		return
	}
	for v in rows {
		delete(v, allocator)
	}
	delete(rows^)
	rows^ = nil
}

load_meta :: proc(allocator := context.allocator) -> (Index_Meta, bool) {
	path := meta_path(context.temp_allocator)
	data, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil {
		return {}, false
	}
	doc, perr := json.parse(data, .JSON, allocator = context.temp_allocator)
	if perr != .None {
		return {}, false
	}
	obj, ok := doc.(json.Object)
	if !ok {
		return {}, false
	}
	meta: Index_Meta
	meta.version = constants.RAG_INDEX_VERSION
	if v, vok := obj["version"]; vok {
		#partial switch n in v {
		case json.Integer:
			meta.version = int(n)
		case json.Float:
			meta.version = int(n)
		}
	}
	if v, vok := obj["embed_provider"]; vok {
		if s, sok := v.(json.String); sok {
			meta.embed_provider = strings.clone(string(s), allocator)
		}
	}
	if v, vok := obj["embed_model"]; vok {
		if s, sok := v.(json.String); sok {
			meta.embed_model = strings.clone(string(s), allocator)
		}
	}
	if v, vok := obj["dim"]; vok {
		#partial switch n in v {
		case json.Integer:
			meta.dim = int(n)
		case json.Float:
			meta.dim = int(n)
		}
	}
	if v, vok := obj["created"]; vok {
		#partial switch n in v {
		case json.Integer:
			meta.created = i64(n)
		case json.Float:
			meta.created = i64(n)
		}
	}
	return meta, true
}

save_meta :: proc(meta: Index_Meta) -> string {
	if mk := ensure_rag_dir(); mk != "" {
		return mk
	}
	path := meta_path(context.temp_allocator)
	tmp := fmt.tprintf("%s.tmp", path)
	body := fmt.tprintf(
		`{{"version":%d,"embed_provider":%q,"embed_model":%q,"dim":%d,"created":%d}}`+"\n",
		meta.version,
		meta.embed_provider,
		meta.embed_model,
		meta.dim,
		meta.created,
	)
	if os.write_entire_file(tmp, transmute([]u8)body) != nil {
		return "rag meta write failed"
	}
	_ = os.remove(path)
	if os.rename(tmp, path) != nil {
		_ = os.remove(tmp)
		return "rag meta rename failed"
	}
	return ""
}

header_mismatch :: proc(meta: Index_Meta) -> bool {
	if meta.version != constants.RAG_INDEX_VERSION {
		return true
	}
	want_prov, want_model, id_err := current_embed_identity(context.temp_allocator)
	defer delete(want_prov, context.temp_allocator)
	defer delete(want_model, context.temp_allocator)
	if len(id_err) > 0 {
		return false
	}
	if len(want_model) > 0 && meta.embed_model != want_model {
		return true
	}
	if len(want_prov) > 0 && meta.embed_provider != want_prov {
		return true
	}
	return false
}

Clear :: proc() -> string {
	_ = os.remove(meta_path(context.temp_allocator))
	_ = os.remove(chunks_path(context.temp_allocator))
	_ = os.remove(vectors_path(context.temp_allocator))
	return ""
}

load_index :: proc(allocator := context.allocator) -> (
	chunks: [dynamic]Chunk_Rec,
	vectors: [dynamic][]f32,
	err: string,
) {
	chunks = make([dynamic]Chunk_Rec, allocator)
	vectors = make([dynamic][]f32, allocator)
	cpath := chunks_path(context.temp_allocator)
	vpath := vectors_path(context.temp_allocator)
	cdata, cerr := os.read_entire_file(cpath, context.temp_allocator)
	if cerr != nil {
		return chunks, vectors, ""
	}
	meta, mok := load_meta(context.temp_allocator)
	defer if mok {
		delete(meta.embed_provider, context.temp_allocator)
		delete(meta.embed_model, context.temp_allocator)
	}
	dim := 0
	if mok {
		dim = meta.dim
	}
	lines := strings.split_lines(string(cdata), context.temp_allocator)
	for line in lines {
		trimmed := strings.trim_space(line)
		if len(trimmed) == 0 {
			continue
		}
		rec, ok := parse_chunk_line(trimmed, allocator)
		if !ok {
			continue
		}
		append(&chunks, rec)
	}
	vdata, verr := os.read_entire_file(vpath, context.temp_allocator)
	if verr != nil {
		if len(chunks) > 0 {
			return chunks, vectors, "rag vectors missing"
		}
		return chunks, vectors, ""
	}
	if dim <= 0 {
		if len(chunks) > 0 && len(vdata) > 0 {
			dim = len(vdata) / (4 * len(chunks))
		}
	}
	if dim <= 0 {
		return chunks, vectors, "rag dim unknown"
	}
	row_bytes := dim * 4
	if len(vdata) < len(chunks) * row_bytes {
		return chunks, vectors, "rag vectors truncated"
	}
	for i in 0 ..< len(chunks) {
		off := i * row_bytes
		row := make([]f32, dim, allocator)
		src := vdata[off:off + row_bytes]
		for j in 0 ..< dim {
			b0 := u32(src[j * 4])
			b1 := u32(src[j * 4 + 1])
			b2 := u32(src[j * 4 + 2])
			b3 := u32(src[j * 4 + 3])
			bits := b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
			row[j] = transmute(f32)bits
		}
		append(&vectors, row)
	}
	return chunks, vectors, ""
}

parse_chunk_line :: proc(line: string, allocator := context.allocator) -> (Chunk_Rec, bool) {
	doc, err := json.parse_string(line, .JSON, allocator = context.temp_allocator)
	if err != .None {
		return {}, false
	}
	obj, ok := doc.(json.Object)
	if !ok {
		return {}, false
	}
	rec: Chunk_Rec
	if v, vok := obj["id"]; vok {
		if s, sok := v.(json.String); sok {
			rec.id = strings.clone(string(s), allocator)
		}
	}
	if v, vok := obj["source"]; vok {
		if s, sok := v.(json.String); sok {
			rec.source = strings.clone(string(s), allocator)
		}
	}
	if v, vok := obj["key"]; vok {
		if s, sok := v.(json.String); sok {
			rec.key = strings.clone(string(s), allocator)
		}
	}
	if v, vok := obj["text"]; vok {
		if s, sok := v.(json.String); sok {
			rec.text = strings.clone(string(s), allocator)
		}
	}
	if v, vok := obj["updated"]; vok {
		#partial switch n in v {
		case json.Integer:
			rec.updated = i64(n)
		case json.Float:
			rec.updated = i64(n)
		}
	}
	if len(rec.id) == 0 || len(rec.text) == 0 {
		delete(rec.id, allocator)
		delete(rec.source, allocator)
		delete(rec.key, allocator)
		delete(rec.text, allocator)
		return {}, false
	}
	return rec, true
}

save_index :: proc(meta: Index_Meta, chunks: []Chunk_Rec, vectors: [][]f32) -> string {
	if len(chunks) != len(vectors) {
		return "rag chunk/vector count mismatch"
	}
	if mk := ensure_rag_dir(); mk != "" {
		return mk
	}
	// GC oldest when over chunk or byte caps.
	keep_n := len(chunks)
	est := keep_n * (meta.dim * 4 + 200)
	for est > constants.RAG_INDEX_BYTES && keep_n > 1 {
		keep_n -= 1
		est = keep_n * (meta.dim * 4 + 200)
	}
	if keep_n > constants.RAG_MAX_CHUNKS {
		keep_n = constants.RAG_MAX_CHUNKS
	}
	start := len(chunks) - keep_n
	if start < 0 {
		start = 0
	}

	cpath := chunks_path(context.temp_allocator)
	vpath := vectors_path(context.temp_allocator)
	ctmp := fmt.tprintf("%s.tmp", cpath)
	vtmp := fmt.tprintf("%s.tmp", vpath)

	cb: strings.Builder
	strings.builder_init(&cb, context.temp_allocator)
	for i in start ..< len(chunks) {
		c := chunks[i]
		fmt.sbprintf(
			&cb,
			`{{"id":%q,"source":%q,"key":%q,"text":%q,"updated":%d}}`+"\n",
			c.id,
			c.source,
			c.key,
			c.text,
			c.updated,
		)
	}
	if werr := os.write_entire_file(ctmp, transmute([]u8)strings.to_string(cb)); werr != nil {
		return fmt.tprintf("rag chunks write failed: %v path=%s", werr, ctmp)
	}

	vbytes := make([dynamic]u8, context.temp_allocator)
	for i in start ..< len(vectors) {
		row := vectors[i]
		if len(row) != meta.dim {
			return "rag vector dim mismatch on save"
		}
		if vector_all_zero(row) {
			return "rag zero vector refused"
		}
		for x in row {
			bits := transmute(u32)x
			append(&vbytes, u8(bits & 0xff))
			append(&vbytes, u8((bits >> 8) & 0xff))
			append(&vbytes, u8((bits >> 16) & 0xff))
			append(&vbytes, u8((bits >> 24) & 0xff))
		}
	}
	if os.write_entire_file(vtmp, vbytes[:]) != nil {
		_ = os.remove(ctmp)
		return "rag vectors write failed"
	}
	_ = os.remove(cpath)
	_ = os.remove(vpath)
	if os.rename(ctmp, cpath) != nil || os.rename(vtmp, vpath) != nil {
		_ = os.remove(ctmp)
		_ = os.remove(vtmp)
		return "rag index rename failed"
	}
	meta2 := meta
	meta2.version = constants.RAG_INDEX_VERSION
	if meta2.created == 0 {
		meta2.created = time.time_to_unix(time.now())
	}
	return save_meta(meta2)
}
