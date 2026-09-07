/*
Session event queue and poll.
*/

package session

import "core:fmt"
import "core:strings"
import "core:sync"
import "nullray:agent"
import "nullray:constants"
import "nullray:provider"

Event_Kind :: enum {
	None,
	Status,
	Assistant_Delta,
	Reasoning_Delta,
	Assistant_Done,
	Assistant_Turn,
	Error,
	Job_Started,
	Tool_Call,
	Tool_Result,
	Stream_Clear,
	Usage,
	Turn_Commit,
}

Event :: struct {
	kind:               Event_Kind,
	text:               string,
	name:               string,
	reasoning:          string,
	prompt_tokens:      int,
	completion_tokens:  int,
	total_tokens:       int,
}

session_enqueue :: proc(s: ^Session, ev: Event) {
	sync.mutex_lock(&s.pending_mu)
	if len(s.pending) >= constants.MAX_PENDING_EVENTS {
		// Drop oldest to bound memory under flood
		old := s.pending[0]
		ordered_remove(&s.pending, 0)
		delete(old.text)
		delete(old.name)
		delete(old.reasoning)
	}
	append(&s.pending, ev)
	sync.mutex_unlock(&s.pending_mu)
}

session_poll :: proc(s: ^Session) -> (changed: bool) {
	sync.mutex_lock(&s.pending_mu)
	if len(s.pending) == 0 {
		sync.mutex_unlock(&s.pending_mu)
		return false
	}
	batch := s.pending
	s.pending = make([dynamic]Event)
	sync.mutex_unlock(&s.pending_mu)

	for ev in batch {
		switch ev.kind {
		case .None:
		case .Status, .Tool_Call:
			session_set_status(s, ev.text)
			changed = true
		case .Stream_Clear:
			session_clear_streaming(s)
			changed = true
		case .Assistant_Delta:
			session_append_delta(s, ev.text)
			session_set_status(s, "streaming")
			changed = true
		case .Reasoning_Delta:
			session_append_thinking(s, ev.text)
			session_set_status(s, "thinking")
			changed = true
		case .Tool_Result:
			session_clear_streaming(s)
			// Live status only. Native tool rows are committed from the job result.
			session_set_status(s, fmt.tprintf("tool %s", ev.name))
			changed = true
		case .Job_Started:
			s.busy = true
			session_clear_streaming(s)
			session_set_status(s, ev.text)
			changed = true
		case .Assistant_Turn:
			session_clear_streaming(s)
			changed = true
		case .Turn_Commit:
			session_apply_pending_commit(s)
			changed = true
		case .Assistant_Done:
			s.busy = false
			think := strings.to_string(s.thinking)
			r := ev.reasoning
			if len(r) == 0 {
				r = think
			}
			session_clear_streaming(s)
			body := ev.text
			owned_body := false
			if s.mode_policy == .Model && len(body) > 0 {
				new_mode, found, cleaned := agent.detect_mode_request(body)
				if found {
					session_set_mode(s, new_mode)
					body = cleaned
					owned_body = true
				} else {
					delete(cleaned)
				}
			}
			if len(body) == 0 && len(r) == 0 && !s.skip_assistant_push {
				session_set_status(s, "error: empty model response")
			} else if s.skip_assistant_push {
				s.skip_assistant_push = false
				if len(body) > 0 && strings.contains(body, "\n\nreview:\n") {
					// Append review-only note as a short assistant line
					idx := strings.index(body, "\n\nreview:\n")
					if idx >= 0 {
						session_push_assistant(s, body[idx + 2:], "")
					}
				}
				session_set_status(s, session_ready_status(s))
			} else {
				session_push_assistant(s, body, r)
				session_set_status(s, session_ready_status(s))
			}
			if owned_body {
				delete(body)
			}
			changed = true
		case .Usage:
			s.last_usage = provider.Usage{
				prompt_tokens = ev.prompt_tokens,
				completion_tokens = ev.completion_tokens,
				total_tokens = ev.total_tokens,
			}
			s.session_usage.prompt_tokens += ev.prompt_tokens
			s.session_usage.completion_tokens += ev.completion_tokens
			s.session_usage.total_tokens += ev.total_tokens
			changed = true
		case .Error:
			s.busy = false
			session_clear_streaming(s)
			session_set_status(s, fmt.tprintf("error: %s", ev.text))
			changed = true
		}
		delete(ev.text)
		delete(ev.name)
		delete(ev.reasoning)
	}
	delete(batch)
	return changed
}
