// SPDX-License-Identifier: 0BSD
package session

import "core:strings"
import "core:time"
import "nullray:constants"
import "nullray:provider"

session_set_status :: proc(s: ^Session, text: string) {
	if text == s.status {
		delete(s.pending_status)
		s.pending_status = ""
		return
	}
	if s.busy && !status_is_urgent(text) && len(s.status) > 0 {
		age := time.tick_diff(s.status_set_at, time.tick_now())
		if age < time.Duration(constants.STATUS_HOLD_MS) * time.Millisecond {
			delete(s.pending_status)
			s.pending_status = strings.clone(text)
			return
		}
	}
	delete(s.pending_status)
	s.pending_status = ""
	delete(s.status)
	s.status = strings.clone(text)
	s.status_set_at = time.tick_now()
}

@(private)
status_is_urgent :: proc(text: string) -> bool {
	if strings.has_prefix(text, "error") {
		return true
	}
	if strings.has_prefix(text, "ready") {
		return true
	}
	if strings.has_prefix(text, "stopping") || strings.has_prefix(text, "pausing") {
		return true
	}
	if strings.has_prefix(text, "running ") {
		return true
	}
	if strings.has_prefix(text, "verify") {
		return true
	}
	if strings.has_prefix(text, "tool ") {
		return true
	}
	return false
}

session_set_live_tool :: proc(s: ^Session, name, detail: string) {
	delete(s.live_tool)
	delete(s.live_tool_detail)
	s.live_tool = strings.clone(name)
	s.live_tool_detail = strings.clone(detail)
}

session_clear_live_tool :: proc(s: ^Session) {
	delete(s.live_tool)
	delete(s.live_tool_detail)
	s.live_tool = ""
	s.live_tool_detail = ""
}

session_tick_status_hold :: proc(s: ^Session) -> bool {
	if len(s.pending_status) == 0 {
		return false
	}
	age := time.tick_diff(s.status_set_at, time.tick_now())
	if age < time.Duration(constants.STATUS_HOLD_MS) * time.Millisecond {
		return false
	}
	next := s.pending_status
	s.pending_status = ""
	delete(s.status)
	s.status = next
	s.status_set_at = time.tick_now()
	return true
}

session_retry_last :: proc(s: ^Session, p: ^provider.Provider) -> bool {
	if s.busy || p == nil {
		return false
	}
	has_user := false
	for i := len(s.messages) - 1; i >= 0; i -= 1 {
		if s.messages[i].role == .User {
			has_user = true
			break
		}
	}
	if !has_user {
		return false
	}
	session_clear_streaming(s)
	session_start_chat(s, p)
	return true
}
