// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Slash commands for scheduled jobs (/schedule, /loop, /remind) plus the
bridge between the schedule package and live sessions. The watcher thread
emits due jobs through app_schedule_emit, which enqueues session Wakeup
events; schedule_tick_poll (app tick) takes delivered wakeups and starts
the chat turn on the UI thread.
*/

package app

import "base:runtime"
import "core:fmt"
import "core:strconv"
import "core:strings"
import "core:sync"
import "nullray:provider"
import "nullray:schedule"
import "nullray:session"

// Session that scheduled wakeups target. Rebound to the active session if
// the bound tab is closed. The watcher thread reads this through the sink
// procs while the UI thread frees sessions in app_tab_close, so every access
// goes through g_sched_mu; the close path holds it across the free so a sink
// call can never hold a stale pointer.
g_sched_mu:   sync.Mutex
g_sched_sess: ^session.Session

// Bound session for scheduled wakeups; nil when none is bound.
@(private)
sched_session :: proc() -> ^session.Session {
	sync.mutex_lock(&g_sched_mu)
	defer sync.mutex_unlock(&g_sched_mu)
	return g_sched_sess
}

@(private)
sched_session_set :: proc(s: ^session.Session) {
	sync.mutex_lock(&g_sched_mu)
	g_sched_sess = s
	sync.mutex_unlock(&g_sched_mu)
}

/*
Rebind or clear the delivery target before the session is freed. Caller is
app_tab_close on the UI thread; must NOT hold g_sched_mu.
*/
app_sched_unbind :: proc(dead, replacement: ^session.Session) {
	sync.mutex_lock(&g_sched_mu)
	defer sync.mutex_unlock(&g_sched_mu)
	if g_sched_sess == dead {
		g_sched_sess = replacement
	}
}

// Sessions currently running a heartbeat turn, so the tab strip and
// notifier stay quiet for unattended beats.
g_hb_mu:      sync.Mutex
g_hb_running: map[^session.Session]bool

app_schedule_bind :: proc(a: ^App) {
	sched_session_set(a.session)
	schedule.schedule_set_wakeup_sink(app_schedule_emit, app_schedule_queued)
	schedule.schedule_set_busy_probe(app_schedule_busy)
	schedule.schedule_set_heartbeat_allowed(a.session.persist)
}

// The sink procs hold g_sched_mu across the session call so app_tab_close
// cannot free the session out from under the watcher thread.
app_schedule_emit :: proc(prompt, tag: string) {
	sync.mutex_lock(&g_sched_mu)
	defer sync.mutex_unlock(&g_sched_mu)
	s := g_sched_sess
	if s == nil {
		return
	}
	session.session_wakeup_tagged(s, prompt, tag)
}

app_schedule_queued :: proc(tag: string) -> int {
	sync.mutex_lock(&g_sched_mu)
	defer sync.mutex_unlock(&g_sched_mu)
	s := g_sched_sess
	if s == nil {
		return 0
	}
	return session.session_wakeup_queued(s, tag)
}

app_schedule_busy :: proc() -> bool {
	sync.mutex_lock(&g_sched_mu)
	defer sync.mutex_unlock(&g_sched_mu)
	s := g_sched_sess
	if s == nil {
		return false
	}
	return s.busy
}

/*
Drain delivered wakeups into chat turns and rebind the delivery session if
its tab closed. Runs before app_poll_tabs so finished heartbeat turns can
be unmarked before the busy-to-idle notification sees them.
*/
schedule_tick_poll :: proc(a: ^App) -> bool {
	changed := false
	if len(a.tabs) == 0 {
		return false
	}
	bound := false
	cur := sched_session()
	for t in a.tabs {
		if t.sess == cur {
			bound = true
			break
		}
	}
	if !bound {
		sched_session_set(a.session)
	}
	if g_hb_running == nil {
		g_hb_running = make(map[^session.Session]bool, 0, runtime.heap_allocator())
	}
	sync.mutex_lock(&g_hb_mu)
	for t, i in a.tabs {
		if g_hb_running[t.sess] && !t.sess.busy {
			delete_key(&g_hb_running, t.sess)
			a.tabs[i].busy_before = t.sess.busy
			a.tabs[i].done_pending = false
			changed = true
		}
	}
	sync.mutex_unlock(&g_hb_mu)
	p := provider.registry_active(&a.registry)
	if p == nil {
		return changed
	}
	for t in a.tabs {
		if t.sess.busy {
			continue
		}
		tag, ok := session.session_wakeup_take(t.sess)
		if !ok {
			continue
		}
		if tag == schedule.HEARTBEAT_TAG {
			sync.mutex_lock(&g_hb_mu)
			g_hb_running[t.sess] = true
			sync.mutex_unlock(&g_hb_mu)
		}
		session.session_start_chat(t.sess, p)
		delete(tag)
		changed = true
	}
	return changed
}

app_schedule_destroy :: proc() {
	schedule.schedule_stop()
	sched_session_set(nil)
	schedule.schedule_destroy()
	sync.mutex_lock(&g_hb_mu)
	delete(g_hb_running)
	g_hb_running = nil
	sync.mutex_unlock(&g_hb_mu)
}

slash_cmd_schedule :: proc(a: ^App, args: string) {
	if !schedule.schedule_enabled() {
		session.session_set_status(a.session, "schedule off (NULLRAY_SCHEDULE=0)")
		return
	}
	parts := strings.fields(strings.trim_space(args), context.temp_allocator)
	if len(parts) == 0 || parts[0] == "list" {
		text := schedule.job_list_text(schedule.unix_now(), context.temp_allocator)
		session.session_set_status(a.session, text)
		return
	}
	if parts[0] == "cancel" {
		if len(parts) < 2 {
			session.session_set_status(a.session, "usage: /schedule cancel ID|all")
			return
		}
		if parts[1] == "all" {
			n := schedule.job_cancel_all()
			session.session_set_status(a.session, fmt.tprintf("cancelled %d job(s)", n))
			return
		}
		n, ok := strconv.parse_int(parts[1])
		if !ok || !schedule.job_cancel(n) {
			session.session_set_status(a.session, fmt.tprintf("no job %s", parts[1]))
			return
		}
		session.session_set_status(a.session, fmt.tprintf("cancelled job %d", n))
		return
	}
	session.session_set_status(a.session, "usage: /schedule [list|cancel ID|all]")
}

// /loop <interval|cron5> <prompt>: recurring scheduled turn.
slash_cmd_loop :: proc(a: ^App, args: string) {
	if !schedule.schedule_enabled() {
		session.session_set_status(a.session, "schedule off (NULLRAY_SCHEDULE=0)")
		return
	}
	parts := strings.fields(strings.trim_space(args), context.temp_allocator)
	if len(parts) < 2 {
		session.session_set_status(a.session, "usage: /loop 30m|1h|cron5 PROMPT")
		return
	}
	spec := ""
	prompt_parts: []string
	if _, ok := schedule.dur_parse(parts[0]); ok {
		spec = fmt.tprintf("every %s", parts[0])
		prompt_parts = parts[1:]
	} else if len(parts) > 5 {
		maybe := strings.join(parts[:5], " ", context.temp_allocator)
		if _, ok := schedule.cron_parse(maybe); ok {
			spec = maybe
			prompt_parts = parts[5:]
		}
	}
	if len(spec) == 0 {
		session.session_set_status(a.session, "usage: /loop 30m|1h|cron5 PROMPT")
		return
	}
	prompt := strings.join(prompt_parts, " ", context.temp_allocator)
	now := schedule.unix_now()
	id, err := schedule.job_add(prompt, spec, a.session.name, false, false, 0, 0, .Prompt, now)
	if len(err) > 0 {
		defer delete(err)
		session.session_set_status(a.session, err)
		return
	}
	in_sec, _ := schedule.job_next_fire_in(id, now)
	session.session_set_status(
		a.session,
		fmt.tprintf("loop job %d (%s), next fire in %s", id, spec, schedule.fmt_delta(in_sec, context.temp_allocator)),
	)
}

// /remind <in> <text>: one-shot scheduled turn.
slash_cmd_remind :: proc(a: ^App, args: string) {
	if !schedule.schedule_enabled() {
		session.session_set_status(a.session, "schedule off (NULLRAY_SCHEDULE=0)")
		return
	}
	parts := strings.fields(strings.trim_space(args), context.temp_allocator)
	if len(parts) < 2 {
		session.session_set_status(a.session, "usage: /remind 10m TEXT")
		return
	}
	if _, ok := schedule.dur_parse(parts[0]); !ok {
		session.session_set_status(a.session, "usage: /remind 10m TEXT")
		return
	}
	prompt := strings.join(parts[1:], " ", context.temp_allocator)
	spec := fmt.tprintf("in %s", parts[0])
	now := schedule.unix_now()
	id, err := schedule.job_add(prompt, spec, a.session.name, false, true, 0, 0, .Prompt, now)
	if len(err) > 0 {
		defer delete(err)
		session.session_set_status(a.session, err)
		return
	}
	session.session_set_status(
		a.session,
		fmt.tprintf("reminder job %d in %s", id, schedule.fmt_delta(
			must_next(id, now), context.temp_allocator)),
	)
}

@(private)
must_next :: proc(id: int, now: i64) -> i64 {
	sec, _ := schedule.job_next_fire_in(id, now)
	return sec
}
