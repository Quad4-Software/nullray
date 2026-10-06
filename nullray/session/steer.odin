// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Mid-turn steer inbox and follow-up queue.
Enter injects into the live turn. Tab queues for after the turn.
Esc still cancels.
*/

package session

import "core:strings"
import "core:sync"

session_push_steer :: proc(s: ^Session, text: string) -> bool {
	if s == nil {
		return false
	}
	t := strings.trim_space(text)
	if len(t) == 0 {
		return false
	}
	sync.mutex_lock(&s.steer_mu)
	defer sync.mutex_unlock(&s.steer_mu)
	append(&s.steer_inbox, strings.clone(t))
	return true
}

session_push_followup :: proc(s: ^Session, text: string) -> bool {
	if s == nil {
		return false
	}
	t := strings.trim_space(text)
	if len(t) == 0 {
		return false
	}
	sync.mutex_lock(&s.steer_mu)
	defer sync.mutex_unlock(&s.steer_mu)
	append(&s.followup_queue, strings.clone(t))
	return true
}

session_poll_steer :: proc(user: rawptr) -> string {
	s := cast(^Session)user
	if s == nil {
		return ""
	}
	sync.mutex_lock(&s.steer_mu)
	defer sync.mutex_unlock(&s.steer_mu)
	if len(s.steer_inbox) == 0 {
		return ""
	}
	b: strings.Builder
	strings.builder_init(&b)
	strings.write_string(&b, "[steer]\n")
	for msg, i in s.steer_inbox {
		if i > 0 {
			strings.write_byte(&b, '\n')
		}
		strings.write_string(&b, msg)
		delete(msg)
	}
	clear(&s.steer_inbox)
	return strings.to_string(b)
}

session_take_followup :: proc(s: ^Session) -> string {
	if s == nil {
		return ""
	}
	sync.mutex_lock(&s.steer_mu)
	defer sync.mutex_unlock(&s.steer_mu)
	if len(s.followup_queue) == 0 {
		return ""
	}
	msg := s.followup_queue[0]
	ordered_remove(&s.followup_queue, 0)
	return msg
}

session_steer_destroy :: proc(s: ^Session) {
	if s == nil {
		return
	}
	sync.mutex_lock(&s.steer_mu)
	defer sync.mutex_unlock(&s.steer_mu)
	for m in s.steer_inbox {
		delete(m)
	}
	delete(s.steer_inbox)
	s.steer_inbox = nil
	for m in s.followup_queue {
		delete(m)
	}
	delete(s.followup_queue)
	s.followup_queue = nil
}
