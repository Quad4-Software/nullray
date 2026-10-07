// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package schedule

import "core:fmt"
import "core:strings"
import "core:sync"
import "nullray:constants"

job_lookup :: proc(id: int) -> (Job, bool) {
	jobs_ensure_init()
	sync.mutex_lock(&g_jobs_mu)
	for j in g_jobs {
		if j.id == id {
			sync.mutex_unlock(&g_jobs_mu)
			return j, true
		}
	}
	sync.mutex_unlock(&g_jobs_mu)
	return {}, false
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
A job whose wakeup is still queued on the target session is not re-emitted,
its next fire is pushed forward so bursts coalesce into one wakeup.
*/
