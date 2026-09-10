// SPDX-License-Identifier: 0BSD
/*
Cancel in-flight work and join the chat job before teardown.
*/

package session

import "core:sync"
import "core:thread"
import "core:time"
import "nullray:constants"
import "nullray:subagent"

session_take_job_thread :: proc(s: ^Session) -> ^thread.Thread {
	sync.mutex_lock(&s.job_mu)
	th := s.job_thread
	s.job_thread = nil
	sync.mutex_unlock(&s.job_mu)
	return th
}

session_join_job :: proc(s: ^Session, wait_ms := -1) -> bool {
	th := session_take_job_thread(s)
	if th == nil {
		return false
	}
	if wait_ms < 0 {
		thread.join(th)
		thread.destroy(th)
		return true
	}
	deadline := time.tick_now()
	limit := time.Millisecond * time.Duration(wait_ms)
	for !thread.is_done(th) {
		if time.tick_since(deadline) > limit {
			// Abandon hung worker. thread.terminate is unsafe with the Odin allocator.
			// Print-mode process exit reclaims the OS thread. Caller clears busy.
			return true
		}
		time.sleep(10 * time.Millisecond)
	}
	thread.join(th)
	thread.destroy(th)
	return true
}

/*
Request cancel, kill shells, join the chat worker, drain events, join subagents.
Safe to call more than once. Call before session_destroy / process exit.
*/
session_shutdown :: proc(s: ^Session, wait_ms := constants.SHUTDOWN_JOIN_MS) {
	if s == nil {
		return
	}
	session_request_cancel(s)
	had_job := session_join_job(s, wait_ms)

	if had_job {
		deadline := time.tick_now()
		limit := time.Millisecond * time.Duration(wait_ms)
		for s.busy {
			_ = session_poll(s)
			if !s.busy {
				break
			}
			if time.tick_since(deadline) > limit {
				break
			}
			time.sleep(10 * time.Millisecond)
		}
	} else if s.busy {
		// No worker owns the turn (tests or a lost handle). Do not block teardown.
		s.busy = false
	}
	_ = session_poll(s)

	if rt := subagent.runtime(); rt != nil {
		subagent.runtime_join_workers(rt, wait_ms)
	}
}
