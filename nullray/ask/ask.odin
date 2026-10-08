// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Out-of-band question channel. A tool blocks on a condvar while a UI
(TUI modal, ACP elicitation, ...) fulfills or cancels the challenge.
Answers never enter tool results unless the tool chooses to return them.
*/

package ask

import "base:runtime"
import "core:strings"
import "core:sync"
import "core:time"

Kind :: enum {
	Text,
	Secret,
	Choice,
	Confirm,
	View, // declarative multi-field form (show_view tool)
}

Challenge :: struct {
	id:        u64,
	kind:      Kind,
	prompt:    string,
	options:   [dynamic]string,
	free_form: bool,
	active:    bool,
	// Owned view schema JSON when kind == .View (cloned at request time).
	view_json: string,
}

challenge_destroy :: proc(c: ^Challenge) {
	delete(c.prompt)
	for o in c.options {
		delete(o)
	}
	delete(c.options)
	delete(c.view_json)
	c^ = {}
}

/*
External transports (ACP elicitation, tests) register a responder. It runs
on the blocked tool thread. Return ok with the answer, cancelled when the
user declined, or !ok when the transport cannot serve the challenge.
*/
Responder :: #type proc(
	kind: Kind,
	prompt: string,
	options: []string,
	user: rawptr,
	allocator := context.allocator,
) -> (
	answer: string,
	ok: bool,
	cancelled: bool,
)

State :: struct {
	mu:             sync.Mutex,
	cond:           sync.Cond,
	challenge:      Challenge,
	answer:         string,
	answered:       bool,
	cancelled:      bool,
	next_id:        u64,
	ui_enabled:     bool,
	responder:      Responder,
	responder_user: rawptr,
}

g_ask: State

set_ui_enabled :: proc(on: bool) {
	sync.mutex_lock(&g_ask.mu)
	defer sync.mutex_unlock(&g_ask.mu)
	g_ask.ui_enabled = on
}

ui_enabled :: proc() -> bool {
	sync.mutex_lock(&g_ask.mu)
	defer sync.mutex_unlock(&g_ask.mu)
	return g_ask.ui_enabled
}

set_responder :: proc(r: Responder, user: rawptr = nil) {
	sync.mutex_lock(&g_ask.mu)
	defer sync.mutex_unlock(&g_ask.mu)
	g_ask.responder = r
	g_ask.responder_user = user
}

/*
Block until a UI or responder fulfills or cancels, or timeout.
Caller owns the returned answer. ok=false means no channel answered.
*/
request :: proc(
	kind: Kind,
	prompt: string,
	options: []string = nil,
	free_form := false,
	timeout_sec: i64 = 600,
	allocator := context.allocator,
) -> (
	answer: string,
	ok: bool,
	cancelled: bool,
) {
	return request_ex(kind, prompt, options, free_form, "", timeout_sec, allocator)
}

// request_ex allows an optional view_json payload for Kind.View challenges.
request_ex :: proc(
	kind: Kind,
	prompt: string,
	options: []string = nil,
	free_form := false,
	view_json: string = "",
	timeout_sec: i64 = 600,
	allocator := context.allocator,
) -> (
	answer: string,
	ok: bool,
	cancelled: bool,
) {
	sync.mutex_lock(&g_ask.mu)
	resp := g_ask.responder
	resp_user := g_ask.responder_user
	sync.mutex_unlock(&g_ask.mu)
	if resp != nil {
		// View payloads are only served by the native TUI channel for now.
		if kind == .View {
			return "", false, false
		}
		return resp(kind, prompt, options, resp_user, allocator)
	}

	sync.mutex_lock(&g_ask.mu)
	defer sync.mutex_unlock(&g_ask.mu)
	if !g_ask.ui_enabled || g_ask.challenge.active {
		return "", false, false
	}

	g_ask.next_id += 1
	challenge_destroy(&g_ask.challenge)
	g_ask.challenge = Challenge{
		id = g_ask.next_id,
		kind = kind,
		prompt = strings.clone(prompt),
		free_form = free_form,
		active = true,
		view_json = strings.clone(view_json),
	}
	g_ask.challenge.options = make([dynamic]string)
	for o in options {
		append(&g_ask.challenge.options, strings.clone(o))
	}
	delete(g_ask.answer, runtime.heap_allocator())
	g_ask.answer = {}
	g_ask.answered = false
	g_ask.cancelled = false

	deadline := time.time_add(time.now(), time.Duration(timeout_sec) * time.Second)
	for !g_ask.answered && !g_ask.cancelled {
		if timeout_sec > 0 && time.diff(deadline, time.now()) >= 0 {
			challenge_destroy(&g_ask.challenge)
			return "", false, true
		}
		_ = sync.cond_wait_with_timeout(&g_ask.cond, &g_ask.mu, 200 * time.Millisecond)
	}

	challenge_destroy(&g_ask.challenge)
	if g_ask.cancelled {
		return "", false, true
	}
	if !g_ask.answered {
		return "", false, false
	}
	ans := strings.clone(g_ask.answer, allocator)
	delete(g_ask.answer, runtime.heap_allocator())
	g_ask.answer = {}
	g_ask.answered = false
	return ans, true, false
}

has_pending :: proc() -> bool {
	sync.mutex_lock(&g_ask.mu)
	defer sync.mutex_unlock(&g_ask.mu)
	return g_ask.challenge.active
}

/*
Poll for the pending challenge. Options slice is owned by the caller
(free each element and the slice). Lives until fulfilled or cancelled.
*/
challenge_pending :: proc(
	allocator := context.allocator,
) -> (
	active: bool,
	id: u64,
	kind: Kind,
	prompt: string,
	options: []string,
	free_form: bool,
) {
	active, id, kind, prompt, options, free_form, _ = challenge_pending_ex(allocator)
	return
}

challenge_pending_ex :: proc(
	allocator := context.allocator,
) -> (
	active: bool,
	id: u64,
	kind: Kind,
	prompt: string,
	options: []string,
	free_form: bool,
	view_json: string,
) {
	sync.mutex_lock(&g_ask.mu)
	defer sync.mutex_unlock(&g_ask.mu)
	if !g_ask.challenge.active {
		return false, 0, .Text, "", nil, false, ""
	}
	opts := make([]string, len(g_ask.challenge.options), allocator)
	for o, i in g_ask.challenge.options {
		opts[i] = strings.clone(o, allocator)
	}
	return true,
		g_ask.challenge.id,
		g_ask.challenge.kind,
		strings.clone(g_ask.challenge.prompt, allocator),
		opts,
		g_ask.challenge.free_form,
		strings.clone(g_ask.challenge.view_json, allocator)
}

fulfill :: proc(id: u64, answer: string) -> bool {
	sync.mutex_lock(&g_ask.mu)
	defer sync.mutex_unlock(&g_ask.mu)
	if !g_ask.challenge.active || g_ask.challenge.id != id {
		return false
	}
	// Heap-pinned: the fulfiller and requester run on different threads with
	// different context allocators, so this slot uses one fixed allocator.
	delete(g_ask.answer, runtime.heap_allocator())
	g_ask.answer = strings.clone(answer, runtime.heap_allocator())
	g_ask.answered = true
	g_ask.cancelled = false
	sync.cond_signal(&g_ask.cond)
	return true
}

cancel :: proc(id: u64 = 0) -> bool {
	sync.mutex_lock(&g_ask.mu)
	defer sync.mutex_unlock(&g_ask.mu)
	if !g_ask.challenge.active {
		return false
	}
	if id != 0 && g_ask.challenge.id != id {
		return false
	}
	g_ask.cancelled = true
	g_ask.answered = false
	delete(g_ask.answer, runtime.heap_allocator())
	g_ask.answer = {}
	sync.cond_signal(&g_ask.cond)
	return true
}
