// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Scheduled-wakeup plumbing. A Wakeup event carries the prompt in text and a
coalescing tag in name. While the session is busy the event stays queued in
s.pending, once drained it becomes a user message and its tag moves to the
delivered set until session_wakeup_take hands it to the app to start the
turn. Session pointers are only map keys, so this never imports schedule.
*/

package session

import "base:runtime"
import "core:strings"
import "core:sync"

g_wakeup_mu:   sync.Mutex
g_wakeup_done: map[^Session][dynamic]string

session_wakeup :: proc(s: ^Session, prompt: string) {
	session_wakeup_tagged(s, prompt, "")
}

session_wakeup_tagged :: proc(s: ^Session, prompt, tag: string) {
	if s == nil || len(prompt) == 0 {
		return
	}
	session_enqueue(s, Event{kind = .Wakeup, text = strings.clone(prompt), name = strings.clone(tag)})
}

// Queued plus delivered-but-not-taken wakeups for a tag.
session_wakeup_queued :: proc(s: ^Session, tag: string) -> int {
	if s == nil {
		return 0
	}
	n := 0
	sync.mutex_lock(&s.pending_mu)
	for ev in s.pending {
		if ev.kind == .Wakeup && ev.name == tag {
			n += 1
		}
	}
	sync.mutex_unlock(&s.pending_mu)
	sync.mutex_lock(&g_wakeup_mu)
	if lst, ok := g_wakeup_done[s]; ok {
		for tg in lst {
			if tg == tag {
				n += 1
			}
		}
	}
	sync.mutex_unlock(&g_wakeup_mu)
	return n
}

@(private)
wakeup_record :: proc(s: ^Session, tag: string) {
	sync.mutex_lock(&g_wakeup_mu)
	if g_wakeup_done == nil {
		g_wakeup_done = make(map[^Session][dynamic]string, 0, runtime.heap_allocator())
	}
	lst := g_wakeup_done[s]
	if lst == nil {
		lst = make([dynamic]string, runtime.heap_allocator())
	}
	append(&lst, strings.clone(tag, runtime.heap_allocator()))
	g_wakeup_done[s] = lst
	sync.mutex_unlock(&g_wakeup_mu)
}

// Pop the oldest delivered wakeup tag. Caller deletes the returned string.
session_wakeup_take :: proc(s: ^Session) -> (tag: string, ok: bool) {
	sync.mutex_lock(&g_wakeup_mu)
	if lst, found := g_wakeup_done[s]; found && len(lst) > 0 {
		tag = lst[0]
		ordered_remove(&lst, 0)
		if len(lst) == 0 {
			delete(lst)
			delete_key(&g_wakeup_done, s)
		} else {
			g_wakeup_done[s] = lst
		}
		sync.mutex_unlock(&g_wakeup_mu)
		return tag, true
	}
	sync.mutex_unlock(&g_wakeup_mu)
	return "", false
}

// Drop delivered-but-untaken wakeups for a session being destroyed.
session_wakeup_forget :: proc(s: ^Session) {
	sync.mutex_lock(&g_wakeup_mu)
	if lst, ok := g_wakeup_done[s]; ok {
		for tg in lst {
			delete(tg, runtime.heap_allocator())
		}
		delete(lst)
		delete_key(&g_wakeup_done, s)
	}
	sync.mutex_unlock(&g_wakeup_mu)
}
