// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Web search providers: a data-driven registry of REST endpoints plus a
generic OpenSearch path. Providers declare a URL template, auth headers,
a JSON body template, and a dotted-path result map, so adding a backend is
a config entry, not code. Provider entries come from builtins, the config
dir, and the workspace file (workspace entries need hooks trust - a
provider URL can exfiltrate queries).

Kinds: "search" for query -> result list, "fetch" for URL -> content
(FlareSolverr, self-hosted scrapers) that fetch_url consults on demand.
*/

package search

import "core:os"
import "core:strings"
import "nullray:constants"

Kind :: enum {
	Search,
	Fetch,
	OpenSearch,
}

Source :: enum {
	Builtin,
	Config,
	Workspace,
}

Provider :: struct {
	id:            string,
	kind:          Kind,
	source:        Source,
	method:        string, // GET or POST
	url:           string, // {query} {limit} {pageno} {lang} placeholders
	headers:       []string, // ${ENV} interpolated at exec time
	body:          string, // JSON template, {query} etc interpolated
	results_path:  string, // dotted path to the result array, "" for RSS/Atom bodies
	map_title:     string,
	map_url:       string,
	map_snippet:   string,
	map_score:     string,
	map_date:      string,
	map_engine:    string,
	env_required:  []string,
	scopes:        []string, // general, code, news; empty = all
	timeout_sec:   int,
	disabled:      bool,
}

Result :: struct {
	title:   string,
	url:     string,
	snippet: string,
	engine:  string,
	score:   f64,
	date:    string,
	provider: string,
}

enabled :: proc() -> bool {
	if v, ok := os.lookup_env(constants.ENV_SEARCH, context.temp_allocator); ok {
		l := strings.to_lower(v, context.temp_allocator)
		if l == "0" || l == "false" || l == "off" {
			return false
		}
	}
	return true
}

// Configured = env_required vars all set. Unkeyed providers pass.
provider_ready :: proc(p: ^Provider) -> bool {
	if p.disabled {
		return false
	}
	for k in p.env_required {
		v, ok := os.lookup_env(k, context.temp_allocator)
		if !ok || len(strings.trim_space(v)) == 0 {
			return false
		}
	}
	return true
}

provider_matches_scope :: proc(p: ^Provider, scope: string) -> bool {
	if len(scope) == 0 || len(p.scopes) == 0 {
		return true
	}
	for s in p.scopes {
		if s == scope {
			return true
		}
	}
	return false
}
