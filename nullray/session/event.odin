// SPDX-License-Identifier: 0BSD
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
import "nullray:store"

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
	reasoning_tokens:   int,
	cost_usd:           f64,
	cost_known:         bool,
	input_chars:        int,
	stopped:            string,
	agent_id:           string,
	harness_calls:      int,
	harness_peak_chars: int,
	harness_stubbed:    int,
	harness_artifacts:  int,
	harness_clear:      int,
	harness_compact:    int,
	harness_midturn:       int,
	harness_writeback:     int,
	harness_tools_json:    int,
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
		delete(old.stopped)
		delete(old.agent_id)
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
		case .Status:
			session_set_status(s, ev.text)
			if strings.has_prefix(ev.text, "verify ok") ||
				strings.has_prefix(ev.text, "verify failed") ||
				strings.has_suffix(ev.text, " done") {
				session_clear_live_tool(s)
			}
			changed = true
		case .Tool_Call:
			session_set_live_tool(s, ev.name, ev.text)
			session_set_status(s, ev.text)
			changed = true
		case .Stream_Clear:
			session_clear_streaming(s)
			changed = true
		case .Assistant_Delta:
			session_clear_live_tool(s)
			session_append_delta(s, ev.text)
			session_set_status(s, "streaming")
			changed = true
		case .Reasoning_Delta:
			session_clear_live_tool(s)
			session_append_thinking(s, ev.text)
			session_set_status(s, "thinking")
			changed = true
		case .Tool_Result:
			session_clear_streaming(s)
			if len(ev.name) > 0 {
				session_set_status(s, fmt.tprintf("%s done", ev.name))
			} else {
				session_set_status(s, "tool done")
			}
			changed = true
		case .Job_Started:
			s.busy = true
			session_clear_live_tool(s)
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
			session_clear_live_tool(s)
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
				reasoning_tokens = ev.reasoning_tokens,
				cost_usd = ev.cost_usd,
				cost_known = ev.cost_known,
			}
			is_child := len(ev.agent_id) > 0 && ev.agent_id != "main"
			if is_child {
				s.subagent_total_tokens += ev.total_tokens
				if store.usage_include_subagents() {
					s.session_usage.prompt_tokens += ev.prompt_tokens
					s.session_usage.completion_tokens += ev.completion_tokens
					s.session_usage.total_tokens += ev.total_tokens
					s.session_usage.reasoning_tokens += ev.reasoning_tokens
					if ev.cost_known {
						s.session_usage.cost_usd += ev.cost_usd
						if !s.session_usage.cost_known && s.usage_turns == 0 {
							s.session_usage.cost_known = true
						}
					} else if ev.prompt_tokens + ev.completion_tokens + ev.total_tokens > 0 {
						s.session_usage.cost_known = false
					}
				}
			} else {
				s.usage_turns += 1
				s.session_usage.prompt_tokens += ev.prompt_tokens
				s.session_usage.completion_tokens += ev.completion_tokens
				s.session_usage.total_tokens += ev.total_tokens
				s.session_usage.reasoning_tokens += ev.reasoning_tokens
				if ev.cost_known {
					s.session_usage.cost_usd += ev.cost_usd
					if s.usage_turns == 1 {
						s.session_usage.cost_known = true
					}
				} else if ev.prompt_tokens + ev.completion_tokens + ev.total_tokens > 0 {
					s.session_usage.cost_known = false
				}
			}
			if ev.input_chars > 0 {
				s.last_input_chars = ev.input_chars
				if ev.input_chars > s.peak_input_chars {
					s.peak_input_chars = ev.input_chars
				}
			}
			if len(ev.stopped) > 0 {
				delete(s.last_stopped)
				s.last_stopped = strings.clone(ev.stopped)
			}
			session_record_turn_usage(s, ev)
			changed = true
		case .Error:
			s.busy = false
			session_clear_live_tool(s)
			session_clear_streaming(s)
			session_set_status(s, fmt.tprintf("error: %s", ev.text))
			changed = true
		}
		delete(ev.text)
		delete(ev.name)
		delete(ev.reasoning)
		delete(ev.stopped)
		delete(ev.agent_id)
	}
	delete(batch)
	return changed
}

session_record_turn_usage :: proc(s: ^Session, ev: Event) {
	path := s.session_path
	persist := store.usage_persist_enabled(s.persist)
	if !persist {
		return
	}
	if !s.persist {
		stamp := s.name
		if len(stamp) == 0 {
			stamp = "ephemeral"
		}
		path = store.ephemeral_usage_path(stamp, context.temp_allocator)
	}
	turn := s.usage_turns
	if len(ev.agent_id) > 0 && ev.agent_id != "main" {
		turn = 0
	}
	_ = store.append_turn_metrics(path, store.Turn_Metrics{
		turn = turn,
		model = s.model,
		agent_id = ev.agent_id,
		prompt_tokens = ev.prompt_tokens,
		completion_tokens = ev.completion_tokens,
		total_tokens = ev.total_tokens,
		reasoning_tokens = ev.reasoning_tokens,
		input_chars = ev.input_chars,
		cost_usd = ev.cost_usd,
		cost_known = ev.cost_known,
		stopped = ev.stopped,
		harness_calls = ev.harness_calls,
		harness_peak_chars = ev.harness_peak_chars,
		harness_stubbed = ev.harness_stubbed,
		harness_artifacts = ev.harness_artifacts,
		harness_clear = ev.harness_clear,
		harness_compact = ev.harness_compact,
		harness_midturn = ev.harness_midturn,
		harness_writeback = ev.harness_writeback,
		harness_tools_json = ev.harness_tools_json,
	})
	session_save_meta(s)
}
