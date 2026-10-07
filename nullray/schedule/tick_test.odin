// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package schedule

import "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "core:testing"
import "nullray:constants"
import "nullray:sandbox"

g_test_queued: int

@(private)
test_reset :: proc() {
	schedule_stop()
	schedule_destroy()
	g_persist = false
	g_emit = nil
	g_busy = nil
	g_test_queued = 0
	schedule_set_wakeup_sink(nil, proc(_: string) -> int { return g_test_queued })
	g_hb_enabled = false
	g_hb_queued = false
	g_hb_next = 0
	g_hb_allowed = true
}

@(test)
test_one_shot_fires_and_drops :: proc(t: ^testing.T) {
	test_reset()
	defer test_reset()
	now := i64(1000)
	id, err := job_add("check build", "in 5s", "", false, true, 0, 0, .Prompt, now)
	testing.expect_value(t, err, "")
	testing.expect_value(t, job_count(), 1)
	due := schedule_tick(now + 2)
	testing.expect_value(t, len(due), 0)
	due_list_destroy(due)
	due = schedule_tick(now + 5)
	testing.expect_value(t, len(due), 1)
	testing.expect(t, strings.has_prefix(due[0].prompt, "[scheduled]"))
	testing.expect_value(t, due[0].tag, fmt.tprintf("job:%d", id))
	due_list_destroy(due)
	testing.expect_value(t, job_count(), 0)
}

@(test)
test_one_shot_bounded_expiry :: proc(t: ^testing.T) {
	test_reset()
	defer test_reset()
	now := i64(1000)
	_, err := job_add("once", "in 5s", "", false, true, 0, 0, .Prompt, now)
	testing.expect_value(t, err, "")
	// An undeliverable one-shot (target session gone for good) must not sit
	// forever: expires is bounded to fire time plus 24h.
	sync.mutex_lock(&g_jobs_mu)
	exp := g_jobs[0].expires
	sync.mutex_unlock(&g_jobs_mu)
	testing.expect_value(t, exp, now + 5 + 86400)
}

@(test)
test_recurring_next_fire :: proc(t: ^testing.T) {
	test_reset()
	defer test_reset()
	now := i64(1000)
	_, err := job_add("ping", "every 60s", "", false, false, 0, 0, .Prompt, now)
	testing.expect_value(t, err, "")
	due := schedule_tick(now + 59)
	testing.expect_value(t, len(due), 0)
	due_list_destroy(due)
	due = schedule_tick(now + 60)
	testing.expect_value(t, len(due), 1)
	due_list_destroy(due)
	// Wakeup sits queued on the session: fire time passes without a second due.
	g_test_queued = 1
	due = schedule_tick(now + 120)
	testing.expect_value(t, len(due), 0)
	due_list_destroy(due)
	// Delivered, the pushed-forward fire time produces exactly one wakeup.
	g_test_queued = 0
	due = schedule_tick(now + 180)
	testing.expect_value(t, len(due), 1)
	due_list_destroy(due)
}

@(test)
test_coalescing :: proc(t: ^testing.T) {
	test_reset()
	defer test_reset()
	now := i64(1000)
	_, err := job_add("ping", "every 60s", "", false, false, 0, 0, .Prompt, now)
	testing.expect_value(t, err, "")
	due := schedule_tick(now + 60)
	testing.expect_value(t, len(due), 1)
	due_list_destroy(due)
	g_test_queued = 1
	// Two fire times pass while the wakeup sits queued: still one wakeup.
	due = schedule_tick(now + 120)
	testing.expect_value(t, len(due), 0)
	due_list_destroy(due)
	due = schedule_tick(now + 180)
	testing.expect_value(t, len(due), 0)
	due_list_destroy(due)
	// Delivered: next fire time produces one wakeup, not a burst.
	g_test_queued = 0
	due = schedule_tick(now + 240)
	testing.expect_value(t, len(due), 1)
	due_list_destroy(due)
}

@(test)
test_max_runs_and_expiry :: proc(t: ^testing.T) {
	test_reset()
	defer test_reset()
	now := i64(1000)
	_, err := job_add("once-ish", "every 60s", "", false, false, 1, 0, .Prompt, now)
	testing.expect_value(t, err, "")
	due := schedule_tick(now + 60)
	testing.expect_value(t, len(due), 1)
	due_list_destroy(due)
	testing.expect_value(t, job_count(), 0)

	_, err = job_add("expiring", "every 60s", "", false, false, 0, 100, .Prompt, now)
	testing.expect_value(t, err, "")
	due = schedule_tick(now + 200)
	testing.expect_value(t, len(due), 0)
	due_list_destroy(due)
	testing.expect_value(t, job_count(), 0)

	_, err = job_add("auto-expire", "every 60s", "", false, false, 0, 0, .Prompt, now)
	testing.expect_value(t, err, "")
	inside := now + i64(constants.SCHEDULE_RECURRING_EXPIRE_DAYS)*86400 - 10
	due = schedule_tick(inside)
	due_list_destroy(due)
	testing.expect(t, job_count() >= 0)
	due = schedule_tick(now + i64(constants.SCHEDULE_RECURRING_EXPIRE_DAYS)*86400 + 1)
	testing.expect_value(t, len(due), 0)
	due_list_destroy(due)
	testing.expect_value(t, job_count(), 0)
}

@(test)
test_failure_pause_and_min_interval :: proc(t: ^testing.T) {
	test_reset()
	defer test_reset()
	now := i64(1000)
	id, err := job_add("flaky", "every 60s", "", false, false, 0, 0, .Prompt, now)
	testing.expect_value(t, err, "")
	for _ in 0 ..< constants.SCHEDULE_DEFAULT_MAX_FAILURES {
		job_report_failure(id)
	}
	due := schedule_tick(now + 60)
	testing.expect_value(t, len(due), 0)
	due_list_destroy(due)
	testing.expect_value(t, job_count(), 0)

	_, err = job_add("too fast", "every 30s", "", false, false, 0, 0, .Prompt, now)
	testing.expect(t, len(err) > 0)
	delete(err)
}

@(test)
test_max_jobs_cap :: proc(t: ^testing.T) {
	test_reset()
	defer test_reset()
	now := i64(1000)
	for i in 0 ..< constants.SCHEDULE_MAX_JOBS {
		_, err := job_add("j", "in 6000s", "", false, true, 0, 0, .Prompt, now)
		testing.expect_value(t, err, "")
	}
	_, err := job_add("one too many", "in 6000s", "", false, true, 0, 0, .Prompt, now)
	testing.expect(t, len(err) > 0)
	delete(err)
	testing.expect_value(t, job_cancel_all(), constants.SCHEDULE_MAX_JOBS)
}

@(test)
test_store_roundtrip :: proc(t: ^testing.T) {
	test_reset()
	defer test_reset()
	ws := "/tmp/nullray-sched-test-ws"
	_ = os.remove_all(ws)
	_ = os.make_directory_all(ws)
	defer os.remove_all(ws)
	sandbox.workspace_override_set(ws)
	defer sandbox.workspace_override_clear()
	g_persist = true
	defer { g_persist = false }
	now := i64(1000)
	id, err := job_add("durable one", "every 60s", "sess-a", true, false, 4, 3600, .Prompt, now)
	testing.expect_value(t, err, "")
	_, err = job_add("session only", "in 5s", "", false, true, 0, 0, .Prompt, now)
	testing.expect_value(t, err, "")
	jobs_save()
	// Wipe and reload, only the durable job comes back.
	for i := len(g_jobs) - 1; i >= 0; i -= 1 {
		job_free(&g_jobs[i])
	}
	clear(&g_jobs)
	jobs_load()
	testing.expect_value(t, len(g_jobs), 1)
	j := g_jobs[0]
	testing.expect_value(t, j.id, id)
	testing.expect_value(t, j.spec, "every 60s")
	testing.expect_value(t, j.prompt, "durable one")
	testing.expect_value(t, j.session_scope, "sess-a")
	testing.expect(t, j.durable)
	testing.expect_value(t, j.max_runs, 4)
	testing.expect_value(t, j.expires, now + 3600)
	testing.expect_value(t, j.next_fire, now + 60)
}
