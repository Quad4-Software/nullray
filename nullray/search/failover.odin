// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Backend selection and rotation. NULLRAY_SEARCH_BACKEND picks an id, a CSV
order, or "auto". 429s park a backend until Retry-After (60s fallback),
other errors just skip. SearXNG default URL is overridable through
NULLRAY_SEARCH_URL so a LAN instance needs no config file.
*/

package search

import "core:os"
import "core:fmt"
import "core:strings"
import "core:time"
import "nullray:constants"

@(private)
cooldown_until: map[string]time.Time

search_count :: proc() -> (calls: int) {
	return g_calls
}
@(private)
g_calls: int

// Ready search providers honoring NULLRAY_SEARCH_BACKEND order.
select_backends :: proc(providers: []Provider, scope: string, allocator := context.allocator) -> []Provider {
	out := make([dynamic]Provider, 0, allocator)
	want, has_want := os.lookup_env(constants.ENV_SEARCH_BACKEND, context.temp_allocator)
	if has_want {
		want = strings.to_lower(strings.trim_space(want), context.temp_allocator)
	}
	if has_want && want != "auto" {
		for tok in strings.split(want, ",", context.temp_allocator) {
			id := strings.trim_space(tok)
			for &p in providers {
				if p.id != id || p.kind == .Fetch {
					continue
				}
				if !provider_ready(&p) {
					continue
				}
				if !provider_matches_scope(&p, scope) {
					continue
				}
				append(&out, p)
			}
		}
		return out[:]
	}
	// auto: every ready provider.
	for &p in providers {
		if p.kind == .Fetch {
			continue
		}
		if !provider_ready(&p) {
			continue
		}
		if !provider_matches_scope(&p, scope) {
			continue
		}
		append(&out, p)
	}
	return out[:]
}

backend_cooled :: proc(id: string) -> bool {
	until, ok := cooldown_until[id]
	return ok && time.diff(until, time.now()) < 0
}

backend_cool :: proc(id: string, retry_after: int) {
	secs := retry_after > 0 ? retry_after : 60
	cooldown_until[id] = time.time_add(time.now(), time.Duration(secs) * time.Second)
}

// Fan out queries over backends, dedupe by URL. Stops after the first
// backend that returns results unless backends len > 1 was explicit.
run_search :: proc(
	queries: []string,
	backends: []Provider,
	scope: string,
	limit: int,
	allocator := context.allocator,
) -> (results: []Result, errs: []string) {
	out := make([dynamic]Result, 0, allocator)
	err_list := make([dynamic]string, 0, allocator)
	seen := make(map[string]bool, context.temp_allocator)
	lim := limit > 0 ? limit : 5
	federated := len(backends) > 1
	for &p in backends {
		if backend_cooled(p.id) {
			continue
		}
		before := len(out)
		for q in queries {
			g_calls += 1
			args := Args{query = q, limit = lim, pageno = 1, lang = "en"}
			res, err, rl, ra := exec_provider(&p, &args, allocator)
			if rl {
				backend_cool(p.id, ra)
				break
			}
			if err != "" {
				append(&err_list, strings.clone(err, allocator))
				break
			}
			for r in res {
				if len(r.url) > 0 && seen[r.url] {
					continue
				}
				if len(r.url) > 0 {
					seen[r.url] = true
				}
				append(&out, r)
			}
		}
		if len(out) > before && !federated {
			break // first working backend wins
		}
	}
	return out[:], err_list[:]
}
