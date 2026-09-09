// SPDX-License-Identifier: 0BSD
/*
Project memory tools.
*/

package tools

import "core:strconv"
import "core:strings"
import "core:fmt"
import "nullray:constants"
import project_memory "nullray:memory"
import "nullray:rag"

tool_memory_get :: proc(args_json: string, allocator := context.allocator) -> (string, string) {
	key, err := json_arg_string(args_json, "key", allocator)
	if err != "" {
		return "", err
	}
	defer delete(key)
	return project_memory.Get(key, allocator)
}

tool_memory_put :: proc(args_json: string, allocator := context.allocator) -> (string, string) {
	key, err := json_arg_string(args_json, "key", allocator)
	if err != "" {
		return "", err
	}
	defer delete(key)
	value, value_err := json_arg_string(args_json, "value", allocator)
	if value_err != "" {
		return "", value_err
	}
	defer delete(value)
	return project_memory.Put(key, value, allocator)
}

tool_memory_search :: proc(args_json: string, allocator := context.allocator) -> (string, string) {
	query, err := json_arg_string(args_json, "query", allocator)
	if err != "" {
		return "", err
	}
	defer delete(query)
	limit_str, limit_err := json_arg_string_optional(args_json, "limit", "", allocator)
	if limit_err != "" {
		return "", limit_err
	}
	defer delete(limit_str)
	limit := constants.MEMORY_SEARCH_DEFAULT_LIMIT
	if len(strings.trim_space(limit_str)) > 0 {
		if n, ok := strconv.parse_int(limit_str); ok {
			limit = n
		}
	}
	q := strings.trim_space(query)
	if rag.semantic_available() {
		lex_dyn := project_memory.search_hits(q, limit, context.temp_allocator)
		defer project_memory.destroy_search_hits(&lex_dyn, context.temp_allocator)
		lex := make([]rag.Lexical_Hit, len(lex_dyn), context.temp_allocator)
		for h, i in lex_dyn {
			lex[i] = rag.Lexical_Hit{key = h.entry.key, value = h.entry.value, key_match = h.key_match}
		}
		hits, note := rag.Hybrid_Search(q, lex, limit, context.temp_allocator)
		defer rag.destroy_hits(&hits, context.temp_allocator)
		b: strings.Builder
		strings.builder_init(&b, allocator)
		if len(note) > 0 {
			fmt.sbprintf(&b, "note: %s\n", note)
			delete(note)
		}
		if len(hits) == 0 {
			strings.write_string(&b, "(no matches)")
			return strings.to_string(b), ""
		}
		for h in hits {
			preview := h.text
			if len(preview) > constants.MEMORY_LIST_PREVIEW_CHARS {
				preview = preview[:constants.MEMORY_LIST_PREVIEW_CHARS]
			}
			fmt.sbprintf(&b, "%.3f | %s | %s\n", h.score, h.key, preview)
		}
		return strings.to_string(b), ""
	}
	result := project_memory.Search(q, limit, allocator)
	return result, ""
}

tool_memory_list :: proc(args_json: string, allocator := context.allocator) -> (string, string) {
	filter, err := json_arg_string_optional(args_json, "filter", "", allocator)
	if err != "" {
		return "", err
	}
	defer delete(filter)
	result := project_memory.List(strings.trim_space(filter), allocator)
	return result, ""
}

tool_memory_delete :: proc(args_json: string, allocator := context.allocator) -> (string, string) {
	key, err := json_arg_string(args_json, "key", allocator)
	if err != "" {
		return "", err
	}
	defer delete(key)
	return project_memory.Delete(key, allocator)
}

tool_memory_forget :: proc(args_json: string, allocator := context.allocator) -> (string, string) {
	key, err := json_arg_string(args_json, "key", allocator)
	if err != "" {
		return "", err
	}
	defer delete(key)
	return project_memory.Forget(key, allocator)
}
