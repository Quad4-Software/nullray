// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Standing watch agents on top of durable scheduled jobs.

A watch is a durable .Prompt job whose wrapped prompt turns each wakeup
into a check: the agent runs web_search/fetch_url, then calls the
watch_checkpoint tool with the run's stable item ids. The checkpoint
diffs against the seen set persisted under .nullray/watch/<id>/
(state.json plus digest.md) so the model never diffs prose. Only new
items land in the digest and earn a notification.

Budget guardrails: max_runs rides the job itself, max_tokens lives in
the watch state and is enforced where turn usage is known (the serve
wakeup path calls watch_record_run after each watch turn). Recurring
watches also honor the shared 7 day auto-expiry from job_add.
*/

package schedule

import "core:encoding/json"
import "core:fmt"
import "core:hash"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:time"
import "nullray:constants"
import "nullray:sandbox"

// Cap on remembered item ids per watch so seen state stays bounded.
WATCH_MAX_SEEN :: 2000
// Lines of digest.md that watch show prints.
WATCH_DIGEST_TAIL :: 60

g_watch_state_mu: sync.Mutex

Watch_State :: struct {
	id:          int,
	title:       string,  // owned: the raw user instruction
	runs:        int,     // wakeup turns recorded by the host
	checks:      int,     // watch_checkpoint calls
	hits:        int,     // checkpoints that found new items
	tokens:      i64,     // cumulative turn tokens
	max_tokens:  i64,     // 0 means unlimited
	seen:        [dynamic]string,  // owned strings
	fingerprint: string,  // owned: hash of the last run's result set
	created:     i64,
	last_run:    i64,
	exhausted:   bool,    // budget tripped, job cancelled
}

WATCH_PROMPT :: `Watch task: %s

You are a standing watch agent that runs on a schedule. Every run:

1. Perform the check above with web_search and fetch_url as needed.
2. Call the watch_checkpoint tool with id %d, passing items as a JSON array of stable identifiers for every currently relevant finding, such as CVE ids, URLs, or exact titles. Add a short note describing what you checked.
3. If watch_checkpoint reports no new items, reply exactly WATCH_OK and nothing else.
4. If it reports new items, reply with one short paragraph covering only the new items. The digest and notification are already handled for you.`

watch_root :: proc(allocator := context.allocator) -> string {
	ws := workspace_root(context.temp_allocator)
	p, err := filepath.join({ws, constants.WATCH_DIR}, allocator)
	if err != nil {
		return strings.clone(constants.WATCH_DIR, allocator)
	}
	return p
}

watch_dir :: proc(id: int, allocator := context.allocator) -> string {
	root := watch_root(context.temp_allocator)
	p, err := filepath.join({root, fmt.tprintf("%d", id)}, allocator)
	if err != nil {
		return strings.clone(fmt.tprintf("%s/%d", constants.WATCH_DIR, id), allocator)
	}
	return p
}

@(private)
watch_state_path :: proc(id: int, allocator := context.allocator) -> string {
	dir := watch_dir(id, context.temp_allocator)
	p, _ := filepath.join({dir, "state.json"}, allocator)
	return p
}

@(private)
watch_digest_path :: proc(id: int, allocator := context.allocator) -> string {
	dir := watch_dir(id, context.temp_allocator)
	p, _ := filepath.join({dir, "digest.md"}, allocator)
	return p
}

watch_exists :: proc(id: int) -> bool {
	if id <= 0 {
		return false
	}
	path := watch_state_path(id, context.temp_allocator)
	_, err := os.stat(path, context.temp_allocator)
	return err == nil
}

// State strings and the seen list allocate on the given allocator, callers
// use the temp arena so nothing needs a per-entry destroy.
watch_checkpoint :: proc(
	id: int,
	items: []string,
	note: string,
	now: i64,
	allocator := context.allocator,
) -> (report: string, new_count: int, err: string) {
	if id <= 0 {
		return "", 0, strings.clone("bad watch id", allocator)
	}
	sync.mutex_lock(&g_watch_state_mu)
	defer sync.mutex_unlock(&g_watch_state_mu)
	st, ok := watch_state_load(id, context.temp_allocator)
	if !ok {
		return "", 0, fmt.aprintf("unknown watch %d (no state under %s)", id, constants.WATCH_DIR, allocator = allocator)
	}
	if st.exhausted {
		return "", 0, fmt.aprintf("watch %d stopped: budget exhausted", id, allocator = allocator)
	}
	// Dedupe the run's ids, order does not matter for set math.
	uniq := make([dynamic]string, context.temp_allocator)
	for it in items {
		s := strings.trim_space(it)
		if len(s) == 0 {
			continue
		}
		dup := false
		for u in uniq {
			if u == s {
				dup = true
				break
			}
		}
		if !dup {
			append(&uniq, s)
		}
	}
	st.checks += 1
	st.last_run = now
	new_items := make([dynamic]string, context.temp_allocator)
	for it in uniq {
		if !seen_contains(&st, it) {
			append(&new_items, it)
		}
	}
	fp := watch_fingerprint(uniq[:], context.temp_allocator)
	// Loaded state lives on the temp arena, assigning drops the old fp.
	st.fingerprint = strings.clone(fp, context.temp_allocator)
	if len(new_items) == 0 {
		_ = watch_state_save(&st)
		return fmt.aprintf("watch %d: no new items (%d checked)", id, len(uniq), allocator = allocator), 0, ""
	}
	for it in new_items {
		append(&st.seen, strings.clone(it, context.temp_allocator))
	}
	for len(st.seen) > WATCH_MAX_SEEN {
		delete(st.seen[0], context.temp_allocator)
		ordered_remove(&st.seen, 0)
	}
	st.hits += 1
	if derr := watch_append_digest(id, note, new_items[:], now); len(derr) > 0 {
		defer delete(derr)
		_ = watch_state_save(&st)
		return "", 0, strings.clone(derr, allocator)
	}
	if serr := watch_state_save(&st); len(serr) > 0 {
		defer delete(serr)
		return "", 0, strings.clone(serr, allocator)
	}
	title := st.title
	if len(title) > 60 {
		title = fmt.tprintf("%s...", title[:60])
	}
	joined := strings.join(new_items[:], ", ", context.temp_allocator)
	report = fmt.aprintf("watch %d (%s): %d new item(s): %s", id, title, len(new_items), joined, allocator = allocator)
	return report, len(new_items), ""
}

// Parse a "job:<id>" wakeup tag into a watch id.
