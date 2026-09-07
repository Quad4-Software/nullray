// SPDX-License-Identifier: 0BSD
/*
Auth failure circuit breaker and single-flight elevate coalesce.
*/

package elevate

import "core:sync"
import "core:time"

Circuit :: struct {
	mu:            sync.Mutex,
	fails:         int,
	locked_until:  time.Time,
	in_flight:     bool,
	window_start:  time.Time,
}

g_circuit: Circuit

circuit_reset_for_test :: proc() {
	sync.mutex_lock(&g_circuit.mu)
	defer sync.mutex_unlock(&g_circuit.mu)
	g_circuit.fails = 0
	g_circuit.locked_until = {}
	g_circuit.in_flight = false
	g_circuit.window_start = {}
}

circuit_try_enter :: proc() -> (ok: bool, reason: Outcome) {
	sync.mutex_lock(&g_circuit.mu)
	defer sync.mutex_unlock(&g_circuit.mu)
	now := time.now()
	if g_circuit.locked_until._nsec != 0 && time.diff(now, g_circuit.locked_until) > 0 {
		return false, .Locked
	}
	if g_circuit.locked_until._nsec != 0 && time.diff(now, g_circuit.locked_until) <= 0 {
		g_circuit.locked_until = {}
		g_circuit.fails = 0
	}
	if g_circuit.in_flight {
		return false, .Busy
	}
	g_circuit.in_flight = true
	return true, .Ticket
}

circuit_leave :: proc() {
	sync.mutex_lock(&g_circuit.mu)
	defer sync.mutex_unlock(&g_circuit.mu)
	g_circuit.in_flight = false
}

circuit_record_success :: proc() {
	sync.mutex_lock(&g_circuit.mu)
	defer sync.mutex_unlock(&g_circuit.mu)
	g_circuit.fails = 0
	g_circuit.locked_until = {}
	g_circuit.window_start = {}
}

circuit_record_failure :: proc() {
	sync.mutex_lock(&g_circuit.mu)
	defer sync.mutex_unlock(&g_circuit.mu)
	now := time.now()
	if g_circuit.window_start._nsec == 0 ||
		time.diff(g_circuit.window_start, now) > time.Duration(lock_secs_from_env()) * time.Second {
		g_circuit.window_start = now
		g_circuit.fails = 0
	}
	g_circuit.fails += 1
	if g_circuit.fails >= max_fails_from_env() {
		g_circuit.locked_until = time.time_add(now, time.Duration(lock_secs_from_env()) * time.Second)
	}
}

circuit_is_locked :: proc() -> bool {
	sync.mutex_lock(&g_circuit.mu)
	defer sync.mutex_unlock(&g_circuit.mu)
	now := time.now()
	return g_circuit.locked_until._nsec != 0 && time.diff(now, g_circuit.locked_until) > 0
}
