// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
web_search and the fetch-side passthroughs (flaresolverr and friends).
Results render as title | url | snippet lines capped by
context_max_chars, the model fetches full text via fetch_url. Paid or
write-adjacent providers stay off the speculate list entirely.
*/

package tools

import "core:fmt"
import "core:strconv"
import "core:strings"
import "nullray:constants"
import nr_search "nullray:search"

tool_web_search :: proc(args_json: string, allocator := context.allocator) -> (string, string) {
	if !nr_search.enabled() {
		return "", strings.clone("web search disabled (NULLRAY_SEARCH=0)", allocator)
	}
	queries := make([dynamic]string, 0, context.temp_allocator)
	if q, err := json_arg_string(args_json, "query", context.temp_allocator); err == "" && len(q) > 0 {
		append(&queries, q)
	}
	if qs, _ := json_arg_strings_optional(args_json, "queries", context.temp_allocator); len(qs) > 0 {
		for q in qs {
			append(&queries, q)
		}
	}
	if len(queries) == 0 {
		return "", strings.clone("missing query", allocator)
	}
	count, _ := json_arg_int_optional(args_json, "count", 5, context.temp_allocator)
	if count <= 0 || count > constants.SEARCH_MAX_RESULTS {
		count = constants.SEARCH_MAX_RESULTS
	}
	scope, _ := json_arg_string_optional(args_json, "scope", "", context.temp_allocator)
	scope = strings.to_lower(strings.trim_space(scope), context.temp_allocator)
	switch scope {
	case "general", "code", "news", "":
	case:
		return "", strings.clone("scope must be general, code, or news", allocator)
	}
	max_chars, _ := json_arg_int_optional(args_json, "context_max_chars", 4000, context.temp_allocator)
	if max_chars <= 0 {
		max_chars = 4000
	}

	providers := nr_search.load_providers(context.temp_allocator)
	want, _ := json_arg_strings_optional(args_json, "backends", context.temp_allocator)
	candidates: []nr_search.Provider
	if len(want) > 0 {
		picked := make([dynamic]nr_search.Provider, 0, context.temp_allocator)
		for b in want {
			for p in providers {
				if p.id == b && p.kind != nr_search.Kind.Fetch {
					append(&picked, p)
				}
			}
		}
		candidates = picked[:]
	} else {
		candidates = nr_search.select_backends(providers, scope, context.temp_allocator)
	}
	if len(candidates) == 0 {
		return "", strings.clone(
			"no web search providers configured. Point NULLRAY_SEARCH_URL at a SearXNG instance (example: http://127.0.0.1:8088) or set a vendor key (TAVILY_API_KEY, BRAVE_SEARCH_API_KEY, KAGI_API_KEY, EXA_API_KEY, PARALLEL_API_KEY, MOJEEK_API_KEY, MARGINALIA_API_KEY). For a known docs URL, call fetch_url directly instead of web_search.",
			allocator,
		)
	}

	res, errs := nr_search.run_search(queries[:], candidates, scope, count, allocator)
	if len(res) == 0 {
		if len(errs) > 0 {
			return "", fmt.aprintf(
				"all backends failed: %s. If you already know the URL, use fetch_url on it.",
				strings.join(errs, "; ", context.temp_allocator),
				allocator = allocator,
			)
		}
		return "", strings.clone(
			"no results. Try a shorter query, or fetch_url on a known documentation URL.",
			allocator,
		)
	}
	return render_search_results(res, max_chars, allocator), ""
}

@(private)
render_search_results :: proc(results: []nr_search.Result, max_chars: int, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	wrote := 0
	for r, i in results {
		snippet := r.snippet
		if len(snippet) > constants.SEARCH_SNIPPET_CHARS {
			snippet = snippet[:constants.SEARCH_SNIPPET_CHARS]
		}
		line := fmt.aprintf("[%d] %s\n    %s\n    %s (%s)\n", i + 1, r.title, r.url, snippet, r.provider, allocator = context.temp_allocator)
		if wrote + len(line) > max_chars {
			fmt.sbprintf(&b, "... truncated at %d chars (context_max_chars)\n", max_chars)
			break
		}
		strings.write_string(&b, line)
		wrote += len(line)
	}
	strings.write_string(&b, "\nfetch_url <url> for full text.")
	return strings.to_string(b)
}
