// SPDX-License-Identifier: 0BSD
/*
RAG tools: status, reindex, query.
*/

package tools

import "core:fmt"
import "core:strconv"
import "core:strings"
import "nullray:constants"
import "nullray:rag"

tool_rag_status :: proc(args_json: string, allocator := context.allocator) -> (string, string) {
	_ = args_json
	return rag.Status(allocator), ""
}

tool_rag_reindex :: proc(args_json: string, allocator := context.allocator) -> (string, string) {
	_ = args_json
	err := rag.Reindex_Memory()
	if len(err) > 0 {
		return "", strings.clone(err, allocator)
	}
	return strings.clone("ok", allocator), ""
}

tool_rag_query :: proc(args_json: string, allocator := context.allocator) -> (string, string) {
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
	limit := constants.RAG_TOP_K
	if len(strings.trim_space(limit_str)) > 0 {
		if n, ok := strconv.parse_int(limit_str); ok {
			limit = n
		}
	}
	hits, qerr := rag.Query(strings.trim_space(query), limit, context.temp_allocator)
	defer rag.destroy_hits(&hits, context.temp_allocator)
	b: strings.Builder
	strings.builder_init(&b, allocator)
	if len(qerr) > 0 {
		fmt.sbprintf(&b, "note: %s\n", qerr)
	}
	if len(hits) == 0 {
		strings.write_string(&b, "(no matches)")
		return strings.to_string(b), ""
	}
	for h in hits {
		preview := h.text
		if len(preview) > 200 {
			preview = preview[:200]
		}
		fmt.sbprintf(&b, "%.3f | %s | %s | %s\n", h.score, h.key, h.source, preview)
	}
	return strings.to_string(b), ""
}
