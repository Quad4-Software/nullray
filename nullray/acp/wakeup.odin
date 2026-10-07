// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Scheduled wakeup delivery for the ACP server (used by nullray serve).

The schedule watcher emits due jobs through a scoped sink bound here:
the job's session_scope routes the wakeup to the session that created it.
Emitted wakeups sit on the session's wake_q until the wake pump drains
them (at most one per session per pass) and starts a synthesized
prompt_worker turn: busy sessions keep the wakeup queued, and the tag
stays counted as queued for the whole turn so recurring jobs coalesce.
*/

package acp

import "core:os"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"
import "nullray:http"
import "nullray:provider"
import "nullray:schedule"

Acp_Wakeup :: struct {
	prompt: string, // owned
	tag:    string, // owned
}

// Cap on queued wakeups per session, oldest are dropped past this.
WAKE_QUEUE_MAX :: 8
// Drain cadence and the sleep slice that keeps shutdown responsive.
WAKE_POLL_MS  :: 1000
WAKE_SLICE_MS :: 50

// The Server a bound sink routes to. One server per process (--acp or
// serve), so a plain pointer suffices, set once by schedule_bind.
g_wake_srv: ^Server

// Queue a wakeup on a session. Callers hold srv.sessions_mu so the
// session cannot be freed mid-push.
wake_push :: proc(s: ^Acp_Session, prompt, tag: string) {
	if s == nil || len(prompt) == 0 {
		return
	}
	sync.mutex_lock(&s.wake_mu)
	defer sync.mutex_unlock(&s.wake_mu)
	for len(s.wake_q) >= WAKE_QUEUE_MAX {
		old := s.wake_q[0]
		delete(old.prompt)
		delete(old.tag)
		ordered_remove(&s.wake_q, 0)
	}
	append(&s.wake_q, Acp_Wakeup{
		prompt = strings.clone(prompt),
		tag    = strings.clone(tag),
	})
}

// Queued plus in-flight wakeup turns for a tag (the schedule coalescing
// probe, called under the schedule job lock).
wake_queued :: proc(s: ^Acp_Session, tag: string) -> int {
	if s == nil {
		return 0
	}
	n := 0
	sync.mutex_lock(&s.wake_mu)
	for w in s.wake_q {
		if w.tag == tag {
			n += 1
		}
	}
	n += s.wake_inflight[tag]
	sync.mutex_unlock(&s.wake_mu)
	return n
}

// Pop the oldest queued wakeup and mark its tag in flight so the job is
// not re-emitted while the turn runs. Returned strings are owned by the
// caller. Caller must hold s.control_mu (pairs with the busy check).
wake_take :: proc(s: ^Acp_Session) -> (prompt, tag: string, ok: bool) {
	sync.mutex_lock(&s.wake_mu)
	defer sync.mutex_unlock(&s.wake_mu)
	if len(s.wake_q) == 0 {
		return "", "", false
	}
	w := s.wake_q[0]
	ordered_remove(&s.wake_q, 0)
	if len(w.tag) > 0 {
		s.wake_inflight[w.tag] += 1
	}
	return w.prompt, w.tag, true
}

// Turn for a tag finished, the job may emit again on its next fire.
wake_done :: proc(s: ^Acp_Session, tag: string) {
	if len(tag) == 0 {
		return
	}
	sync.mutex_lock(&s.wake_mu)
	defer sync.mutex_unlock(&s.wake_mu)
	if n := s.wake_inflight[tag]; n <= 1 {
		delete_key(&s.wake_inflight, tag)
	} else {
		s.wake_inflight[tag] = n - 1
	}
}

// Free the wakeup queue at session_destroy (session is already unlinked).
wake_clear :: proc(s: ^Acp_Session) {
	sync.mutex_lock(&s.wake_mu)
	for w in s.wake_q {
		delete(w.prompt)
		delete(w.tag)
	}
	delete(s.wake_q)
	delete(s.wake_inflight)
	sync.mutex_unlock(&s.wake_mu)
}

// Resolve a wakeup target: the scoped session, else the most recently
// prompted session, else any live session. Caller holds sessions_mu.
wake_target :: proc(srv: ^Server, scope: string) -> ^Acp_Session {
	if len(scope) > 0 {
		if s, ok := srv.sessions[scope]; ok {
			return s
		}
	}
	if srv.wake_fallback != nil {
		return srv.wake_fallback
	}
	for _, s in srv.sessions {
		return s
	}
	return nil
}

// Scoped emit sink for the schedule watcher. Runs on the watcher thread.
// When no session exists yet (fresh daemon, no client ever prompted) a
// daemon-owned "daemon" session is created so durable watches and one-shots
// still run headless.
acp_schedule_emit :: proc(prompt, tag, scope: string) {
	srv := g_wake_srv
	if srv == nil {
		return
	}
	sync.mutex_lock(&srv.sessions_mu)
	defer sync.mutex_unlock(&srv.sessions_mu)
	target := wake_target(srv, scope)
	if target == nil {
		cwd, _ := os.get_working_directory(context.temp_allocator)
		target = session_new(srv, "daemon", cwd)
		srv.sessions[target.id] = target
		srv.wake_fallback = target
	}
	wake_push(target, prompt, tag)
}

// Scoped queued probe, runs under the schedule job lock during ticks.
acp_schedule_queued :: proc(tag, scope: string) -> int {
	srv := g_wake_srv
	if srv == nil {
		return 0
	}
	sync.mutex_lock(&srv.sessions_mu)
	defer sync.mutex_unlock(&srv.sessions_mu)
	return wake_queued(wake_target(srv, scope), tag)
}

// Wire the schedule package to this server and start the drain pump.
// Called by run_serve after server_runtime_init when the scheduler is on.
schedule_bind :: proc(srv: ^Server) {
	if srv == nil || srv.wake_pump != nil {
		return
	}
	g_wake_srv = srv
	schedule.schedule_set_wakeup_sink_scoped(acp_schedule_emit, acp_schedule_queued)
	srv.wake_pump = thread.create_and_start_with_data(srv, wake_pump_main, nil, .Normal, false)
}

wake_pump_main :: proc(data: rawptr) {
	srv := cast(^Server)data
	for {
		for _ in 0 ..< WAKE_POLL_MS / WAKE_SLICE_MS {
			if wake_pump_stopped(srv) {
				return
			}
			time.sleep(time.Duration(WAKE_SLICE_MS) * time.Millisecond)
		}
		if wake_pump_stopped(srv) {
			return
		}
		wake_pump_drain(srv)
	}
}

@(private)
wake_pump_stopped :: proc(srv: ^Server) -> bool {
	sync.mutex_lock(&srv.in_mu)
	defer sync.mutex_unlock(&srv.in_mu)
	return srv.eof || srv.stop
}

// One drain pass: at most one wakeup turn per session so a burst of due
// jobs does not stampede a session.
wake_pump_drain :: proc(srv: ^Server) {
	p := provider.registry_active(&srv.providers)
	if p == nil || p.chat == nil {
		return
	}
	// sessions_mu is held for the whole pass: it is the liveness guard,
	// and nothing inside takes a lock that reaches back for it.
	sync.mutex_lock(&srv.sessions_mu)
	defer sync.mutex_unlock(&srv.sessions_mu)
	for _, s in srv.sessions {
		wake_start_turn(srv, s, p)
	}
}

// If the session is idle and has a queued wakeup, push it as a user
// message and start a synthesized prompt_worker turn. Caller holds
// sessions_mu, this takes control_mu then wake_mu (leaf order).
wake_start_turn :: proc(srv: ^Server, s: ^Acp_Session, p: ^provider.Provider) {
	sync.mutex_lock(&s.control_mu)
	defer sync.mutex_unlock(&s.control_mu)
	if s.busy {
		return
	}
	prompt, tag, ok := wake_take(s)
	if !ok {
		return
	}
	defer delete(prompt)
	s.busy = true
	s.cancel_requested = false
	// Clear the http cancel owner flag too, a stale session/cancel makes
	// the wakeup turn fail instantly with "cancelled".
	http.cancel_clear(rawptr(s))
	if s.worker != nil {
		append(&s.retired, s.worker)
		s.worker = nil
	}
	append(&s.messages, provider.Message{role = .User, content = strings.clone(prompt)})

	args := new(Prompt_Args)
	args.srv = srv
	args.sess = s
	args.conn = s.owner
	args.from_wakeup = true
	args.wake_tag = tag
	args.model = strings.clone(s.model)
	args.prov = prompt_provider_copy(srv, p)

	th := thread.create_and_start_with_data(args, prompt_worker, nil, .Normal, false)
	if th == nil {
		s.busy = false
		wake_done(s, tag)
		provider.provider_destroy(&args.prov)
		delete(args.wake_tag)
		delete(args.model)
		free(args)
		return
	}
	s.worker = th
}
