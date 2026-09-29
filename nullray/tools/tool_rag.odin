// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
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
	scope, serr := json_arg_string_optional(args_json, "scope", "memory", allocator)
	if serr != "" {
		return "", serr
	}
	defer delete(scope)
	scope_l := strings.to_lower(strings.trim_space(scope), context.temp_allocator)
	b: strings.Builder
	strings.builder_init(&b, allocator)
	if scope_l == "code" || scope_l == "all" {
		msg := rag.Reindex_Code(allocator)
		strings.write_string(&b, msg)
		delete(msg, allocator)
	}
	if scope_l == "memory" || scope_l == "all" || scope_l == "" {
		err := rag.Reindex_Memory()
		if len(err) > 0 {
			if strings.builder_len(b) > 0 {
				strings.write_string(&b, "; ")
			}
			strings.write_string(&b, err)
		} else if scope_l != "code" && scope_l != "all" {
			strings.write_string(&b, "ok")
		} else {
			if strings.builder_len(b) > 0 {
				strings.write_string(&b, "; ")
			}
			strings.write_string(&b, "memory ok")
		}
	}
	out := strings.to_string(b)
	if len(out) == 0 {
		return strings.clone("ok", allocator), ""
	}
	if strings.contains(out, "unavailable") || strings.contains(out, "disabled") || strings.contains(out, "off") {
		return out, ""
	}
	return out, ""
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
	scope, scope_err := json_arg_string_optional(args_json, "scope", "all", allocator)
	if scope_err != "" {
		return "", scope_err
	}
	defer delete(scope)
	scope_l := strings.to_lower(strings.trim_space(scope), context.temp_allocator)
	prefix := ""
	switch scope_l {
	case "code":
		prefix = rag.CODE_SOURCE_PREFIX
	case "memory":
		prefix = "memory:"
	case "all", "":
	case:
		return "", strings.clone("scope must be all|memory|code", allocator)
	}
	hits, qerr := rag.query_scoped(strings.trim_space(query), limit, prefix, context.temp_allocator)
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
