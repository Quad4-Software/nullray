// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package schedule

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:sync"
import "nullray:constants"

watch_id_from_tag :: proc(tag: string) -> (int, bool) {
	if !strings.has_prefix(tag, "job:") {
		return 0, false
	}
	n, ok := strconv.parse_int(tag[4:])
	if !ok || n <= 0 {
		return 0, false
	}
	return n, true
}

/*
Turn-end accounting for watch jobs, called by the serve wakeup path with
the turn's token spend. On max_tokens the watch is marked exhausted, the
job cancelled, and a note returned for the caller to surface. "" means
nothing worth reporting.
*/
watch_record_run :: proc(id: int, tokens: i64, now: i64, allocator := context.allocator) -> string {
	if id <= 0 || !watch_exists(id) {
		return ""
	}
	sync.mutex_lock(&g_watch_state_mu)
	defer sync.mutex_unlock(&g_watch_state_mu)
	st, ok := watch_state_load(id, context.temp_allocator)
	if !ok {
		return ""
	}
	st.runs += 1
	if tokens > 0 {
		st.tokens += tokens
	}
	st.last_run = now
	if st.max_tokens > 0 && st.tokens >= st.max_tokens && !st.exhausted {
		st.exhausted = true
		_ = watch_state_save(&st)
		watch_append_digest_note(id, "budget exhausted: token cap reached, watch cancelled", now)
		job_cancel(id)
		return fmt.aprintf(
			"watch %d hit token budget %d and was cancelled",
			id, st.max_tokens, allocator = allocator,
		)
	}
	_ = watch_state_save(&st)
	return ""
}

// Split leading spec tokens off args. Accepts "every 2h" as one or two
// tokens, a bare duration meaning every, "at HH:MM", "in 10m", or a
// 5-field cron. spec is allocated on the caller allocator.
watch_spec_parse :: proc(tokens: []string, allocator := context.allocator) -> (spec: string, rest: []string, err: string) {
	if len(tokens) == 0 {
		return "", nil, strings.clone("watch add needs <spec> <instruction>", allocator)
	}
	t0 := tokens[0]
	if t0 == "every" || t0 == "in" || t0 == "at" {
		if len(tokens) < 2 {
			return "", nil, strings.clone("spec needs a value", allocator)
		}
		cand := fmt.tprintf("%s %s", t0, tokens[1])
		if _, ok := spec_next_fire(cand, unix_now()); !ok {
			return "", nil, fmt.aprintf("bad watch spec: %s", cand, allocator = allocator)
		}
		return strings.clone(cand, allocator), tokens[2:], ""
	}
	if _, ok := dur_parse(t0); ok {
		return fmt.aprintf("every %s", t0, allocator = allocator), tokens[1:], ""
	}
	if len(tokens) >= 5 {
		cand := strings.join(tokens[:5], " ", context.temp_allocator)
		if _, ok := cron_parse(cand); ok {
			return strings.clone(cand, allocator), tokens[5:], ""
		}
	}
	// Single token forms like "every 2h" arriving quoted in one argv.
	if _, ok := spec_next_fire(t0, unix_now()); ok {
		return strings.clone(t0, allocator), tokens[1:], ""
	}
	return "", nil, fmt.aprintf("bad watch spec: %s", t0, allocator = allocator)
}

// Wrap the user instruction in the watch protocol prompt.
watch_prompt :: proc(id: int, instruction: string, allocator := context.allocator) -> string {
	return fmt.aprintf(WATCH_PROMPT, strings.trim_space(instruction), id, allocator = allocator)
}

/*
Register a standing watch: durable recurring job plus per-watch state.
The job id doubles as the watch id and is embedded in the prompt so the
agent can call watch_checkpoint without guessing.
*/
watch_add :: proc(
	instruction, spec, scope: string,
	max_runs: int,
	max_tokens: i64,
	expires_in_sec: i64,
	now: i64,
) -> (id: int, err: string) {
	trimmed := strings.trim_space(instruction)
	if len(trimmed) == 0 {
		return 0, strings.clone("watch instruction required")
	}
	nid, aerr := job_add("watch", spec, scope, true, false, max_runs, expires_in_sec, .Prompt, now)
	if len(aerr) > 0 {
		return 0, aerr
	}
	prompt := watch_prompt(nid, trimmed, context.temp_allocator)
	job_set_prompt(nid, prompt)
	st := Watch_State{
		id = nid,
		title = trimmed,
		max_tokens = max_tokens,
		created = now,
	}
	serr := watch_state_save(&st)
	if len(serr) > 0 {
		job_cancel(nid)
		return 0, serr
	}
	return nid, ""
}

// Drop the job and its .nullray/watch/<id> state dir.
watch_rm :: proc(id: int) -> bool {
	removed := job_cancel(id)
	dir := watch_dir(id, context.temp_allocator)
	if os.exists(dir) {
		_ = os.remove_all(dir)
		removed = true
	}
	return removed
}

@(private)
watch_ids :: proc(allocator := context.allocator) -> []int {
	root := watch_root(context.temp_allocator)
	fis, rerr := os.read_all_directory_by_path(root, context.temp_allocator)
	if rerr != nil {
		return nil
	}
	defer os.file_info_slice_delete(fis, context.temp_allocator)
	out := make([dynamic]int, allocator)
	for fi in fis {
		if fi.type != .Directory {
			continue
		}
		if n, ok := strconv.parse_int(fi.name); ok && n > 0 {
			append(&out, n)
		}
	}
	slice.sort(out[:])
	return out[:]
}

watch_list_text :: proc(now: i64, allocator := context.allocator) -> string {
	jobs_ensure_init()
	ids := watch_ids(context.temp_allocator)
	b := strings.builder_make(allocator)
	if len(ids) == 0 {
		strings.write_string(&b, "no watches (add one: nullray watch add <every> <check>)")
		return strings.to_string(b)
	}
	for id in ids {
		st, ok := watch_state_load(id, context.temp_allocator)
		j, jok := job_lookup(id)
		next := "-"
		exp := "-"
		runs := 0
		spec := "job gone"
		if jok {
			spec = j.spec
			next = fmt_delta(max(i64(0), j.next_fire - now), context.temp_allocator)
			if j.expires > 0 {
				exp = fmt_delta(max(i64(0), j.expires - now), context.temp_allocator)
			}
			runs = j.run_count
		}
		fmt.sbprintf(
			&b,
			"watch %d: %s | next in %s | expires in %s | runs %d checks %d hits %d | tokens %d",
			id, spec, next, exp, runs, st.checks, st.hits, st.tokens,
		)
		if st.max_tokens > 0 {
			fmt.sbprintf(&b, "/%d", st.max_tokens)
		}
		if st.exhausted {
			strings.write_string(&b, " | EXHAUSTED")
		}
		fmt.sbprintf(&b, " | %s\n", st.title)
	}
	return strings.to_string(b)
}

// State summary plus the tail of .nullray/watch/<id>/digest.md.
watch_show_text :: proc(id: int, allocator := context.allocator) -> string {
	st, ok := watch_state_load(id, context.temp_allocator)
	if !ok {
		return fmt.aprintf("no watch %d", id, allocator = allocator)
	}
	b := strings.builder_make(allocator)
	fmt.sbprintf(
		&b,
		"watch %d: %s | runs %d checks %d hits %d | tokens %d",
		id, st.title, st.runs, st.checks, st.hits, st.tokens,
	)
	if st.max_tokens > 0 {
		fmt.sbprintf(&b, "/%d", st.max_tokens)
	}
	if st.exhausted {
		strings.write_string(&b, " | EXHAUSTED")
	}
	if len(st.fingerprint) > 0 {
		fmt.sbprintf(&b, " | fp %s", st.fingerprint)
	}
	strings.write_byte(&b, '\n')
	path := watch_digest_path(id, context.temp_allocator)
	data, rerr := os.read_entire_file(path, context.temp_allocator)
	if rerr != nil || len(strings.trim_space(string(data))) == 0 {
		strings.write_string(&b, "(no digest yet: nothing new so far)\n")
		return strings.to_string(b)
	}
	lines := strings.split(strings.trim_right_space(string(data)), "\n", context.temp_allocator)
	start := 0
	if len(lines) > WATCH_DIGEST_TAIL {
		start = len(lines) - WATCH_DIGEST_TAIL
		fmt.sbprintf(&b, "(last %d of %d digest lines)\n", WATCH_DIGEST_TAIL, len(lines))
	}
	for line in lines[start:] {
		strings.write_string(&b, line)
		strings.write_byte(&b, '\n')
	}
	return strings.to_string(b)
}
