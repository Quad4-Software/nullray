// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Provider registry: builtin table plus search_providers.json merges. Same
rules as harnesses: config dir file merges over builtins, workspace file
only merges when hooks trust is granted.
*/

package search

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "nullray:constants"
import "nullray:hooks"
import "nullray:sandbox"

// Builtin providers. url/body/header fields accept {query} {limit}
// {pageno} {lang} placeholders and ${ENV} secrets.
BUILTIN_PROVIDERS := []Provider{
	{
		id = "searxng", kind = .Search, source = .Builtin,
		method = "GET",
		url = "http://127.0.0.1:8080/search?q={query}&format=json&safesearch=0",
		results_path = "results",
		map_title = "title", map_url = "url", map_snippet = "content",
		map_score = "score", map_engine = "engine",
		timeout_sec = 10,
		scopes = []string{"general", "code", "news"},
	},
	{
		id = "tavily", kind = .Search, source = .Builtin,
		method = "POST",
		url = "https://api.tavily.com/search",
		headers = []string{"Authorization: Bearer ${TAVILY_API_KEY}", "Content-Type: application/json"},
		body = `{"query":"{query}","max_results":{limit},"search_depth":"basic"}`,
		results_path = "results",
		map_title = "title", map_url = "url", map_snippet = "content",
		map_score = "score",
		env_required = []string{"TAVILY_API_KEY"},
		timeout_sec = 15,
		scopes = []string{"general", "code", "news"},
	},
	{
		id = "brave", kind = .Search, source = .Builtin,
		method = "GET",
		url = "https://api.search.brave.com/res/v1/web/search?q={query}&count={limit}",
		headers = []string{"X-Subscription-Token: ${BRAVE_SEARCH_API_KEY}", "Accept: application/json"},
		results_path = "web.results",
		map_title = "title", map_url = "url", map_snippet = "description",
		env_required = []string{"BRAVE_SEARCH_API_KEY"},
		timeout_sec = 15,
		scopes = []string{"general", "code"},
	},
	{
		id = "exa", kind = .Search, source = .Builtin,
		method = "POST",
		url = "https://api.exa.ai/search",
		headers = []string{"x-api-key: ${EXA_API_KEY}", "Content-Type: application/json"},
		body = `{"query":"{query}","numResults":{limit},"type":"auto","contents":{"text":{"maxCharacters":400}}}`,
		results_path = "results",
		map_title = "title", map_url = "url", map_snippet = "text",
		env_required = []string{"EXA_API_KEY"},
		timeout_sec = 20,
		scopes = []string{"general", "code"},
	},
	{
		id = "kagi", kind = .Search, source = .Builtin,
		method = "POST",
		url = "https://kagi.com/api/v1/search",
		headers = []string{"Authorization: Bearer ${KAGI_API_KEY}", "Content-Type: application/json"},
		body = `{"query":"{query}","limit":{limit},"workflow":"search"}`,
		results_path = "data.search",
		map_title = "title", map_url = "url", map_snippet = "snippet",
		map_date = "time",
		env_required = []string{"KAGI_API_KEY"},
		timeout_sec = 15,
		scopes = []string{"general", "code", "news"},
	},
	{
		id = "kagi-enrich", kind = .Search, source = .Builtin,
		method = "GET",
		url = "https://kagi.com/api/v0/enrich/web?q={query}",
		headers = []string{"Authorization: Bot ${KAGI_API_KEY}"},
		results_path = "data",
		map_title = "title", map_url = "url", map_snippet = "snippet",
		env_required = []string{"KAGI_API_KEY"},
		timeout_sec = 15,
		scopes = []string{"general"},
	},
	{
		id = "parallel", kind = .Search, source = .Builtin,
		method = "POST",
		url = "https://api.parallel.ai/v1beta/search",
		headers = []string{"x-api-key: ${PARALLEL_API_KEY}", "Content-Type: application/json"},
		body = `{"objective":"{query}","processor":"base","max_results":{limit},"max_chars_per_result":400}`,
		results_path = "results",
		map_title = "title", map_url = "url", map_snippet = "excerpts.0",
		env_required = []string{"PARALLEL_API_KEY"},
		timeout_sec = 20,
		scopes = []string{"general", "code"},
	},
	{
		id = "tinyfish", kind = .Search, source = .Builtin,
		method = "POST",
		url = "https://agent.tinyfish.ai/v1/web-search",
		headers = []string{"Content-Type: application/json"},
		body = `{"query":"{query}","max_results":{limit}}`,
		results_path = "results",
		map_title = "title", map_url = "url", map_snippet = "description",
		timeout_sec = 20,
		scopes = []string{"general"},
	},
	{
		id = "mojeek", kind = .Search, source = .Builtin,
		method = "GET",
		url = "https://www.mojeek.com/services/search/web?api_key=${MOJEEK_API_KEY}&q={query}&fmt=json",
		results_path = "response.results",
		map_title = "title", map_url = "url", map_snippet = "desc",
		env_required = []string{"MOJEEK_API_KEY"},
		timeout_sec = 15,
		scopes = []string{"general"},
	},
	{
		id = "marginalia", kind = .Search, source = .Builtin,
		method = "GET",
		url = "https://api2.marginalia-search.com/search?query={query}&count={limit}",
		headers = []string{"API-Key: ${MARGINALIA_API_KEY}"},
		results_path = "results",
		map_title = "title", map_url = "url", map_snippet = "description",
		env_required = []string{"MARGINALIA_API_KEY"},
		timeout_sec = 15,
		scopes = []string{"general"},
	},
	{
		id = "firecrawl", kind = .Search, source = .Builtin,
		method = "POST",
		// ${FIRECRAWL_API_URL} may point at a self-hosted instance.
		url = "${FIRECRAWL_API_URL}https://api.firecrawl.dev/v2/search",
		headers = []string{"Authorization: Bearer ${FIRECRAWL_API_KEY}", "Content-Type: application/json"},
		body = `{"query":"{query}","limit":{limit}}`,
		results_path = "data",
		map_title = "title", map_url = "url", map_snippet = "description",
		timeout_sec = 20,
		scopes = []string{"general"},
	},
	{
		id = "grepapp", kind = .Search, source = .Builtin,
		method = "GET",
		url = "https://grep.app/api/search?q={query}",
		results_path = "hits.hits",
		map_title = "{hit.repo.raw} {hit.path.raw}",
		map_url = "https://github.com/{hit.repo.raw}/blob/{hit.ref.raw}/{hit.path.raw}",
		map_snippet = "hit.content.snippet",
		timeout_sec = 15,
		scopes = []string{"code"},
	},
	{
		id = "flaresolverr", kind = .Fetch, source = .Builtin,
		method = "POST",
		// FLARESOLVERR_URL must be set, e.g. http://host:8191
		url = "${FLARESOLVERR_URL}/v1",
		headers = []string{"Content-Type: application/json"},
		body = `{"cmd":"request.get","url":"{url}","maxTimeout":60000}`,
		results_path = "solution.response",
		env_required = []string{"FLARESOLVERR_URL"},
		timeout_sec = 65,
	},
}

load_providers :: proc(allocator := context.allocator) -> []Provider {
	out := make([dynamic]Provider, 0, allocator)
	index := make(map[string]int, context.temp_allocator)
	for p in BUILTIN_PROVIDERS {
		append(&out, p)
		index[strings.clone(p.id, context.temp_allocator)] = len(out) - 1
	}

	cfg := sandbox.resolve_config_dir(context.temp_allocator)
	global_path, gerr := filepath.join({cfg, constants.SEARCH_PROVIDERS_FILE}, context.temp_allocator)
	if gerr == nil {
		_ = merge_file(&out, &index, global_path, .Config, allocator)
	}

	if hooks.hooks_workspace_trusted() {
		ws := search_workspace_dir(context.temp_allocator)
		local_path, lerr := filepath.join({ws, ".nullray", constants.SEARCH_PROVIDERS_FILE}, context.temp_allocator)
		if lerr == nil && local_path != global_path {
			_ = merge_file(&out, &index, local_path, .Workspace, allocator)
		}
	}
	// NULLRAY_SEARCH_URL repoints the searxng builtin for LAN instances.
	if base, ok := os.lookup_env(constants.ENV_SEARCH_URL, context.temp_allocator); ok {
		b := strings.trim_suffix(base, "/")
		for &p in out {
			if p.id == "searxng" {
				p.url = strings.concatenate({b, "/search?q={query}&format=json&safesearch=0{extra}"}, context.temp_allocator)
			}
		}
	}
	return out[:]
}

@(private)
search_workspace_dir :: proc(allocator := context.allocator) -> string {
	if ws := sandbox.workspace_current(); len(ws) > 0 {
		return strings.clone(ws, allocator)
	}
	if cwd, err := os.get_working_directory(allocator); err == nil {
		return cwd
	}
	return strings.clone(".", allocator)
}

@(private)
merge_file :: proc(
	out: ^[dynamic]Provider,
	index: ^map[string]int,
	path: string,
	source: Source,
	allocator := context.allocator,
) -> string {
	data, rerr := os.read_entire_file(path, context.temp_allocator)
	if rerr != nil {
		return ""
	}
	defer delete(data, context.temp_allocator)
	doc, perr := json.parse_string(string(data), .JSON, allocator = context.temp_allocator)
	if perr != nil {
		return fmt.aprintf("search providers %s parse failed: %v", path, perr, allocator = allocator)
	}
	obj, is_obj := doc.(json.Object)
	if !is_obj {
		return fmt.aprintf("search providers %s must be a JSON object", path, allocator = allocator)
	}
	for id, val in obj {
		entry, ok := val.(json.Object)
		if !ok {
			continue
		}
		apply_entry(out, index, id, entry, source, allocator)
	}
	return ""
}

@(private)
jstr :: proc(entry: json.Object, key: string) -> (string, bool) {
	s, ok := entry[key].(json.String)
	return s, ok
}

@(private)
jstr_list :: proc(entry: json.Object, key: string, out: ^[dynamic]string, allocator := context.allocator) {
	if a, ok := entry[key].(json.Array); ok {
		for v in a {
			if s, ok := v.(json.String); ok {
				append(out, strings.clone(s, allocator))
			}
		}
	}
	if s, ok := entry[key].(json.String); ok {
		append(out, strings.clone(s, allocator))
	}
}

@(private)
apply_entry :: proc(
	out: ^[dynamic]Provider,
	index: ^map[string]int,
	id: string,
	entry: json.Object,
	source: Source,
	allocator := context.allocator,
) {
	if !valid_id(id) {
		return
	}
	p: Provider
	existing, has := index[id]
	if has {
		p = out[existing]
	} else {
		p.id = strings.clone(id, allocator)
		index[id] = len(out)
	}
	p.source = source
	if s, ok := jstr(entry, "kind"); ok {
		switch strings.to_lower(s, context.temp_allocator) {
		case "search":     p.kind = .Search
		case "fetch":      p.kind = .Fetch
		case "opensearch": p.kind = .OpenSearch
		}
	}
	if s, ok := jstr(entry, "method"); ok {
		p.method = strings.clone(strings.to_upper(s, context.temp_allocator), allocator)
	}
	if s, ok := jstr(entry, "url"); ok {
		p.url = strings.clone(s, allocator)
	}
	h_tmp := make([dynamic]string, 0, context.temp_allocator)
	if a, ok := entry["headers"].(json.Array); ok {
		for h in a {
			if hs, ok := h.(json.String); ok {
				append(&h_tmp, hs)
			}
		}
	}
	if o, ok := entry["headers"].(json.Object); ok {
		for k, v in o {
			if vs, ok := v.(json.String); ok {
				append(&h_tmp, fmt.aprintf("%s: %s", k, vs, allocator = context.temp_allocator))
			}
		}
	}
	if len(h_tmp) > 0 {
		p.headers = slice_clone(h_tmp[:], allocator)
	}
	if s, ok := jstr(entry, "body"); ok {
		p.body = strings.clone(s, allocator)
	}
	if o, ok := entry["body"].(json.Object); ok {
		tmp, _ := json.marshal(o, allocator = allocator)
		p.body = strings.clone(string(tmp), allocator)
	}
	if s, ok := jstr(entry, "results_path"); ok {
		p.results_path = strings.clone(s, allocator)
	}
	if mo, ok := entry["map"].(json.Object); ok {
		if s, ok2 := jstr(mo, "title"); ok2 { p.map_title = strings.clone(s, allocator) }
		if s, ok2 := jstr(mo, "url"); ok2 { p.map_url = strings.clone(s, allocator) }
		if s, ok2 := jstr(mo, "snippet"); ok2 { p.map_snippet = strings.clone(s, allocator) }
		if s, ok2 := jstr(mo, "score"); ok2 { p.map_score = strings.clone(s, allocator) }
		if s, ok2 := jstr(mo, "date"); ok2 { p.map_date = strings.clone(s, allocator) }
		if s, ok2 := jstr(mo, "engine"); ok2 { p.map_engine = strings.clone(s, allocator) }
	}
	e_tmp := make([dynamic]string, 0, context.temp_allocator)
	jstr_list(entry, "env_required", &e_tmp, context.temp_allocator)
	if len(e_tmp) > 0 {
		p.env_required = slice_clone(e_tmp[:], allocator)
	}
	s_tmp := make([dynamic]string, 0, context.temp_allocator)
	jstr_list(entry, "scopes", &s_tmp, context.temp_allocator)
	if len(s_tmp) > 0 {
		p.scopes = slice_clone(s_tmp[:], allocator)
	}
	if f, ok := entry["timeout_sec"].(json.Float); ok {
		p.timeout_sec = int(f)
	}
	if b, ok := entry["disabled"].(json.Boolean); ok {
		p.disabled = bool(b)
	}
	if !has {
		append(out, p)
	} else {
		out[existing] = p
	}
}

valid_id :: proc(id: string) -> bool {
	if len(id) == 0 || len(id) > 64 {
		return false
	}
	for i in 0 ..< len(id) {
		c := id[i]
		switch c {
		case 'a' ..= 'z', 'A' ..= 'Z', '0' ..= '9', '-', '_', '.':
		case:
			return false
		}
	}
	return true
}


@(private)
slice_clone :: proc(items: []string, allocator := context.allocator) -> []string {
	out := make([]string, len(items), allocator)
	for s, i in items {
		out[i] = strings.clone(s, allocator)
	}
	return out
}
