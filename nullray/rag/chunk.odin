// SPDX-License-Identifier: 0BSD
/*
Text chunking and model-aware prefixes.
*/

package rag

import "core:fmt"
import "core:strings"
import "nullray:constants"

chunk_char_limit :: proc(model: string) -> int {
	m := strings.to_lower(model, context.temp_allocator)
	if strings.contains(m, "minilm") {
		return constants.RAG_MAX_CHUNK_CHARS_MINILM
	}
	return constants.RAG_MAX_CHUNK_CHARS
}

uses_nomic_prefixes :: proc(model: string) -> bool {
	m := strings.to_lower(model, context.temp_allocator)
	return strings.contains(m, "nomic-embed")
}

prefix_document :: proc(model, text: string, allocator := context.allocator) -> string {
	if uses_nomic_prefixes(model) {
		return fmt.aprintf("search_document: %s", text, allocator = allocator)
	}
	return strings.clone(text, allocator)
}

prefix_query :: proc(model, text: string, allocator := context.allocator) -> string {
	if uses_nomic_prefixes(model) {
		return fmt.aprintf("search_query: %s", text, allocator = allocator)
	}
	return strings.clone(text, allocator)
}

/*
Split text into overlapping chunks. Caller owns returned strings.
*/
chunk_text :: proc(text, model: string, allocator := context.allocator) -> [dynamic]string {
	out := make([dynamic]string, allocator)
	trimmed := strings.trim_space(text)
	if len(trimmed) == 0 {
		return out
	}
	limit := chunk_char_limit(model)
	overlap := constants.RAG_CHUNK_OVERLAP
	if overlap >= limit {
		overlap = limit / 4
	}
	if len(trimmed) <= limit {
		append(&out, strings.clone(trimmed, allocator))
		return out
	}
	start := 0
	for start < len(trimmed) {
		end := start + limit
		if end > len(trimmed) {
			end = len(trimmed)
		}
		// Prefer breaking at whitespace near the end.
		if end < len(trimmed) {
			cut := end
			for i := end; i > start + limit / 2; i -= 1 {
				if trimmed[i - 1] == ' ' || trimmed[i - 1] == '\n' || trimmed[i - 1] == '\t' {
					cut = i
					break
				}
			}
			end = cut
		}
		piece := strings.trim_space(trimmed[start:end])
		if len(piece) > 0 {
			append(&out, strings.clone(piece, allocator))
		}
		if end >= len(trimmed) {
			break
		}
		next := end - overlap
		if next <= start {
			next = end
		}
		start = next
	}
	return out
}

destroy_string_list :: proc(list: ^[dynamic]string, allocator := context.allocator) {
	if list == nil {
		return
	}
	for s in list {
		delete(s, allocator)
	}
	delete(list^)
	list^ = nil
}
