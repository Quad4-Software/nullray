// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
In-memory scheduled job store and the tick that resolves due work.

Delivery is decoupled through callback procs (schedule_set_wakeup_sink) so
this package never imports session or tools: the app wires a sink that
enqueues session Wakeup events plus a queued-count probe for coalescing.
Durable jobs persist to .nullray/scheduled_tasks.json (see store.odin).
*/

package schedule

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "nullray:constants"

Job_Kind :: enum {
	Prompt,
	Heartbeat,
}

Job :: struct {
	id:            int,
	spec:          string,
	prompt:        string,
	session_scope: string,
	durable:       bool,
	one_shot:      bool,
	max_runs:      int,
	run_count:     int,
	fail_count:    int,
	next_fire:     i64,
	expires:       i64,
	kind:          Job_Kind,
	wakeup_queued: bool,
}

g_jobs_mu:  sync.Mutex
g_jobs:     [dynamic]Job
g_next_id:  int
g_inited:   bool
// Set when a durable job's persisted fields changed since the last save.
// Session-scoped jobs are never written, so their churn must not dirty the
// store (that rewrote scheduled_tasks.json on every in-memory tick).
g_dirty:    bool
g_persist:  bool = true

schedule_enabled :: proc() -> bool {
	if v, ok := os.lookup_env(constants.ENV_SCHEDULE, context.temp_allocator); ok {
		switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
		case "0", "off", "false", "no":
			return false
		}
	}
	return true
}

jobs_ensure_init :: proc() {
	sync.mutex_lock(&g_jobs_mu)
	if !g_inited {
		g_inited = true
		g_next_id = 1
		g_jobs = make([dynamic]Job, runtime.heap_allocator())
		jobs_load()
	}
	sync.mutex_unlock(&g_jobs_mu)
}

schedule_init :: proc() {
	jobs_ensure_init()
}

@(private)
job_free :: proc(j: ^Job) {
	delete(j.spec, runtime.heap_allocator())
	delete(j.prompt, runtime.heap_allocator())
	delete(j.session_scope, runtime.heap_allocator())
	j^ = {}
}

@(private)
job_remove_at :: proc(i: int) {
	if g_jobs[i].durable {
		g_dirty = true
	}
	job_free(&g_jobs[i])
	ordered_remove(&g_jobs, i)
}



/*
Add a job. now anchors first fire and auto-expiry. Errors are allocated on
the caller allocator; delete them.
*/
job_add :: proc(
	prompt, spec, scope: string,
	durable, one_shot: bool,
	max_runs: int,
	expires_in_sec: i64,
	kind: Job_Kind,
	now: i64,
) -> (id: int, err: string) {
	jobs_ensure_init()
	if len(strings.trim_space(prompt)) == 0 {
		return 0, fmt.aprintf("prompt required")
	}
	next, ok := spec_next_fire(spec, now)
	if !ok || next <= now {
		return 0, fmt.aprintf("bad schedule spec: %s", spec)
	}
	recurring := spec_recurring(spec) && !one_shot
	if recurring {
		if ivl, iv_ok := spec_interval_sec(spec); iv_ok && ivl < constants.SCHEDULE_MIN_INTERVAL_SEC {
			return 0, fmt.aprintf(
				"interval %ds below minimum %ds",
				ivl,
				constants.SCHEDULE_MIN_INTERVAL_SEC,
			)
		}
	}
	sync.mutex_lock(&g_jobs_mu)
	if len(g_jobs) >= constants.SCHEDULE_MAX_JOBS {
		sync.mutex_unlock(&g_jobs_mu)
		return 0, fmt.aprintf("job limit %d reached", constants.SCHEDULE_MAX_JOBS)
	}
	j := Job{
		id = g_next_id,
		spec = strings.clone(spec, runtime.heap_allocator()),
		prompt = strings.clone(prompt, runtime.heap_allocator()),
		session_scope = strings.clone(scope, runtime.heap_allocator()),
		durable = durable,
		one_shot = one_shot || !recurring,
		max_runs = max_runs,
		next_fire = next,
		kind = kind,
	}
	g_next_id += 1
	if expires_in_sec > 0 {
		j.expires = now + expires_in_sec
	} else if recurring {
		j.expires = now + i64(constants.SCHEDULE_RECURRING_EXPIRE_DAYS) * 86400
	} else {
		// One-shots with an undeliverable wakeup (target session gone for
		// good) must not live forever: bound them to fire time plus a day.
		j.expires = next + 86400
	}
	append(&g_jobs, j)
	if j.durable {
		g_dirty = true
	}
	sync.mutex_unlock(&g_jobs_mu)
	if j.durable {
		jobs_save()
	}
	return j.id, ""
}

job_cancel :: proc(id: int) -> bool {
	jobs_ensure_init()
	sync.mutex_lock(&g_jobs_mu)
	for i in 0 ..< len(g_jobs) {
		if g_jobs[i].id == id {
			was_durable := g_jobs[i].durable
			job_remove_at(i)
			sync.mutex_unlock(&g_jobs_mu)
			if was_durable {
				jobs_save()
			}
			return true
		}
	}
	sync.mutex_unlock(&g_jobs_mu)
	return false
}

job_cancel_all :: proc() -> int {
	jobs_ensure_init()
	sync.mutex_lock(&g_jobs_mu)
	n := len(g_jobs)
	had_durable := false
	for i := len(g_jobs) - 1; i >= 0; i -= 1 {
		if g_jobs[i].durable {
			had_durable = true
		}
		job_free(&g_jobs[i])
	}
	clear(&g_jobs)
	if had_durable {
		g_dirty = true
	}
	sync.mutex_unlock(&g_jobs_mu)
	if had_durable {
		jobs_save()
	}
	return n
}

job_count :: proc() -> int {
	jobs_ensure_init()
	sync.mutex_lock(&g_jobs_mu)
	n := len(g_jobs)
	sync.mutex_unlock(&g_jobs_mu)
	return n
}

job_report_failure :: proc(id: int) {
	jobs_ensure_init()
	sync.mutex_lock(&g_jobs_mu)
	durable_hit := false
	for &j in g_jobs {
		if j.id == id {
			j.fail_count += 1
			if j.durable {
				g_dirty = true
				durable_hit = true
			}
			break
		}
	}
	sync.mutex_unlock(&g_jobs_mu)
	if durable_hit {
		jobs_save()
	}
}

// Seconds until a job next fires, for user-facing text.
job_next_fire_in :: proc(id: int, now: i64) -> (sec: i64, ok: bool) {
	jobs_ensure_init()
	sync.mutex_lock(&g_jobs_mu)
	for j in g_jobs {
		if j.id == id {
			sync.mutex_unlock(&g_jobs_mu)
			return max(i64(0), j.next_fire - now), true
		}
	}
	sync.mutex_unlock(&g_jobs_mu)
	return 0, false
}

job_list_text :: proc(now: i64, allocator := context.allocator) -> string {
	jobs_ensure_init()
	b := strings.builder_make(allocator)
	sync.mutex_lock(&g_jobs_mu)
	if len(g_jobs) == 0 {
		strings.write_string(&b, "no scheduled jobs")
	}
	for j in g_jobs {
		delta := j.next_fire - now
		if delta < 0 {
			delta = 0
		}
		flags := ""
		if j.durable {
			flags = " durable"
		}
		if j.one_shot {
			flags = strings.concatenate({flags, " once"}, context.temp_allocator)
		}
		fmt.sbprintf(
			&b,
			"job %d: %s | next in %s | runs %d%s | %s\n",
			j.id,
			j.spec,
			fmt_delta(delta, context.temp_allocator),
			j.run_count,
			flags,
			j.prompt,
		)
	}
	hb := heartbeat_status(context.temp_allocator)
	if len(hb) > 0 {
		strings.write_string(&b, hb)
	}
	sync.mutex_unlock(&g_jobs_mu)
	return strings.to_string(b)
}

fmt_delta :: proc(sec: i64, allocator := context.allocator) -> string {
	if sec < 60 {
		return fmt.aprintf("%ds", sec, allocator = allocator)
	}
	if sec < 3600 {
		return fmt.aprintf("%dm", sec / 60, allocator = allocator)
	}
	if sec < 86400 {
		return fmt.aprintf("%dh", sec / 3600, allocator = allocator)
	}
	return fmt.aprintf("%dd", sec / 86400, allocator = allocator)
}

/*
Housekeeping plus due-job resolution. Marks run_count, reschedules recurring
jobs on their last fire time, and drops expired, exhausted, or failed jobs.
A job whose wakeup is still queued on the target session is not re-emitted;
its next fire is pushed forward so bursts coalesce into one wakeup.
*/
schedule_tick :: proc(now: i64, allocator := context.allocator) -> []Due {
	jobs_ensure_init()
	due := make([dynamic]Due, allocator)
	sync.mutex_lock(&g_jobs_mu)
	i := 0
	for i < len(g_jobs) {
		j := &g_jobs[i]
		if (j.expires > 0 && now >= j.expires) ||
			j.fail_count >= constants.SCHEDULE_DEFAULT_MAX_FAILURES {
			job_remove_at(i)
			continue
		}
		if now < j.next_fire {
			i += 1
			continue
		}
		tag := fmt.tprintf("job:%d", j.id)
		if j.wakeup_queued {
			if wakeup_still_queued(tag, j.session_scope) {
				if !j.one_shot {
					if next, ok := spec_next_fire(j.spec, now); ok {
						j.next_fire = next
					}
				}
				i += 1
				continue
			}
			j.wakeup_queued = false
		}
		text := j.prompt
		if j.kind == .Prompt {
			text = fmt.tprintf("[scheduled] %s", j.prompt)
		}
		append(&due, Due{
			id = j.id,
			tag = strings.clone(tag, allocator),
			prompt = strings.clone(text, allocator),
			scope = strings.clone(j.session_scope, allocator),
			kind = j.kind,
		})
		j.run_count += 1
		j.wakeup_queued = true
		if j.durable {
			g_dirty = true
		}
		if j.one_shot || (j.max_runs > 0 && j.run_count >= j.max_runs) {
			job_remove_at(i)
			continue
		}
		next, ok := spec_next_fire(j.spec, j.next_fire)
		if !ok || next <= now {
			next, ok = spec_next_fire(j.spec, now)
		}
		if !ok {
			job_remove_at(i)
			continue
		}
		j.next_fire = next
		i += 1
	}
	heartbeat_tick(now, &due, allocator)
	dirty := g_dirty
	g_dirty = false
	sync.mutex_unlock(&g_jobs_mu)
	if dirty {
		jobs_save()
	}
	return due[:]
}

schedule_destroy :: proc() {
	sync.mutex_lock(&g_jobs_mu)
	for i := len(g_jobs) - 1; i >= 0; i -= 1 {
		job_free(&g_jobs[i])
	}
	delete(g_jobs)
	g_jobs = nil
	g_inited = false
	g_dirty = false
	g_next_id = 1
	sync.mutex_unlock(&g_jobs_mu)
}
