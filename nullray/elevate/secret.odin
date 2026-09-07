// SPDX-License-Identifier: 0BSD
/*
Out-of-band password channel for TUI askpass. Never exposed to tool results.
*/

package elevate

import "core:sync"
import "core:time"
import "core:strings"

Challenge :: struct {
	id:      u64,
	prompt:  string,
	command: string,
	active:  bool,
}

Secret_State :: struct {
	mu:          sync.Mutex,
	cond:        sync.Cond,
	challenge:   Challenge,
	password:    string,
	answered:    bool,
	cancelled:   bool,
	next_id:     u64,
	ui_enabled:  bool,
}

g_secret: Secret_State

secret_init :: proc() {
	g_secret.ui_enabled = true
}

secret_set_ui_enabled :: proc(on: bool) {
	sync.mutex_lock(&g_secret.mu)
	defer sync.mutex_unlock(&g_secret.mu)
	g_secret.ui_enabled = on
}

secret_ui_enabled :: proc() -> bool {
	sync.mutex_lock(&g_secret.mu)
	defer sync.mutex_unlock(&g_secret.mu)
	return g_secret.ui_enabled
}

/*
Block until the UI fulfills or cancels, or timeout. Caller owns returned password.
*/
request_password :: proc(
	prompt: string,
	command: string,
	timeout_sec: i64,
	allocator := context.allocator,
) -> (password: string, ok: bool, cancelled: bool) {
	sync.mutex_lock(&g_secret.mu)
	defer sync.mutex_unlock(&g_secret.mu)

	if !g_secret.ui_enabled || headless() {
		return "", false, false
	}
	if g_secret.challenge.active {
		return "", false, false
	}

	g_secret.next_id += 1
	id := g_secret.next_id
	delete(g_secret.challenge.prompt)
	delete(g_secret.challenge.command)
	g_secret.challenge = Challenge{
		id = id,
		prompt = strings.clone(prompt),
		command = strings.clone(command),
		active = true,
	}
	delete(g_secret.password)
	g_secret.password = {}
	g_secret.answered = false
	g_secret.cancelled = false

	deadline := time.time_add(time.now(), time.Duration(timeout_sec) * time.Second)
	for !g_secret.answered && !g_secret.cancelled {
		now := time.now()
		if time.diff(now, deadline) >= 0 {
			g_secret.challenge.active = false
			delete(g_secret.challenge.prompt)
			delete(g_secret.challenge.command)
			g_secret.challenge.prompt = {}
			g_secret.challenge.command = {}
			return "", false, true
		}
		_ = sync.cond_wait_with_timeout(&g_secret.cond, &g_secret.mu, 200 * time.Millisecond)
	}

	g_secret.challenge.active = false
	delete(g_secret.challenge.prompt)
	delete(g_secret.challenge.command)
	g_secret.challenge.prompt = {}
	g_secret.challenge.command = {}

	if g_secret.cancelled {
		return "", false, true
	}
	if !g_secret.answered || len(g_secret.password) == 0 {
		return "", false, false
	}
	pw := strings.clone(g_secret.password, allocator)
	zero_and_delete(g_secret.password)
	g_secret.password = {}
	g_secret.answered = false
	return pw, true, false
}

challenge_pending :: proc(allocator := context.allocator) -> (active: bool, id: u64, prompt: string, command: string) {
	sync.mutex_lock(&g_secret.mu)
	defer sync.mutex_unlock(&g_secret.mu)
	if !g_secret.challenge.active {
		return false, 0, "", ""
	}
	return true, g_secret.challenge.id,
		strings.clone(g_secret.challenge.prompt, allocator),
		strings.clone(g_secret.challenge.command, allocator)
}

fulfill_password :: proc(id: u64, password: string) -> bool {
	sync.mutex_lock(&g_secret.mu)
	defer sync.mutex_unlock(&g_secret.mu)
	if !g_secret.challenge.active || g_secret.challenge.id != id {
		return false
	}
	delete(g_secret.password)
	g_secret.password = strings.clone(password)
	g_secret.answered = true
	g_secret.cancelled = false
	sync.cond_signal(&g_secret.cond)
	return true
}

cancel_challenge :: proc(id: u64 = 0) -> bool {
	sync.mutex_lock(&g_secret.mu)
	defer sync.mutex_unlock(&g_secret.mu)
	if !g_secret.challenge.active {
		return false
	}
	if id != 0 && g_secret.challenge.id != id {
		return false
	}
	g_secret.cancelled = true
	g_secret.answered = false
	delete(g_secret.password)
	g_secret.password = {}
	sync.cond_signal(&g_secret.cond)
	return true
}

fulfill_password_zero_src :: proc(id: u64, password: string) -> bool {
	ok := fulfill_password(id, password)
	zero_bytes(password)
	return ok
}
