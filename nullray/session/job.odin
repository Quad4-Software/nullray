// SPDX-License-Identifier: 0BSD
/*
Background chat job, turn commit, cancel/pause/resume.
*/

package session

import "core:fmt"
import "core:strings"
import "core:sync"
import "core:thread"
import "nullray:agent"
import "nullray:http"
import "nullray:provider"
import "nullray:store"
import "nullray:subagent"
import "nullray:tools"

Job_Args :: struct {
	session:           ^Session,
	prov:              provider.Provider,
	messages:          []provider.Message,
	tools_enabled:     bool,
	reasoning_effort:  string,
	turn_base:         int,
	prep_stats:        agent.Prepare_Stats,
}

session_apply_pending_commit :: proc(s: ^Session) {
	sync.mutex_lock(&s.commit_mu)
	defer sync.mutex_unlock(&s.commit_mu)
	base := s.turn_base
	if base < 0 {
		base = 0
	}
	if base > len(s.messages) {
		base = len(s.messages)
	}
	for len(s.messages) > base {
		last := s.messages[len(s.messages) - 1]
		provider.destroy_message(last)
		pop(&s.messages)
	}
	for m in s.pending_commit {
		append(&s.messages, m)
	}
	clear(&s.pending_commit)
	s.skip_assistant_push = true
	session_maybe_persist(s)
	cap_messages(s)
}

session_queue_commit :: proc(s: ^Session, turn_base: int, msgs: []provider.Message) {
	sync.mutex_lock(&s.commit_mu)
	for m in s.pending_commit {
		provider.destroy_message(m)
	}
	clear(&s.pending_commit)
	s.turn_base = turn_base
	for m in msgs {
		if m.role == .System {
			continue
		}
		cloned := provider.clone_message(m)
		append(&s.pending_commit, cloned)
	}
	sync.mutex_unlock(&s.commit_mu)
	session_enqueue(s, Event{kind = .Turn_Commit})
}

session_request_cancel :: proc(s: ^Session) {
	sync.mutex_lock(&s.control_mu)
	s.cancel_requested = true
	s.pause_requested = false
	sync.mutex_unlock(&s.control_mu)
	http.cancel_request()
	tools.shell_cancel_active()
	if rt := subagent.runtime(); rt != nil {
		subagent.roster_cancel_children_of(&rt.roster, "main")
	}
	session_set_status(s, "stopping...")
}

session_request_pause :: proc(s: ^Session) {
	sync.mutex_lock(&s.control_mu)
	s.pause_requested = true
	sync.mutex_unlock(&s.control_mu)
	session_set_status(s, "pausing...")
}

session_clear_control :: proc(s: ^Session) {
	sync.mutex_lock(&s.control_mu)
	s.cancel_requested = false
	s.pause_requested = false
	sync.mutex_unlock(&s.control_mu)
	http.cancel_clear()
}

session_stop_check :: proc(user: rawptr) -> agent.Stop_Kind {
	s := cast(^Session)user
	sync.mutex_lock(&s.control_mu)
	defer sync.mutex_unlock(&s.control_mu)
	if s.cancel_requested {
		return .Cancel
	}
	if s.pause_requested {
		return .Pause
	}
	return .None
}

session_resume :: proc(s: ^Session, p: ^provider.Provider, extra := "") {
	if s.busy || p == nil {
		return
	}
	msg := "Continue from where you left off. Use the prior tool results and transcript as context. Do not restart the whole task."
	if len(extra) > 0 {
		msg = fmt.tprintf("%s\n\nAdditional instructions: %s", msg, extra)
	}
	session_push_user(s, msg)
	session_start_chat(s, p)
}

session_start_chat :: proc(s: ^Session, p: ^provider.Provider) {
	if s.busy || p == nil || p.chat == nil {
		return
	}
	session_join_job(s)
	session_clear_control(s)
	s.busy = true

	session_rebuild_system_prompt(s)
	session_remember_model(s, p.id, p.default_model)

	sys_count := 0
	if len(s.system_prompt) > 0 {
		sys_count = 1
	}
	group_ctx := ""
	if len(s.group) > 0 && group_context_from_env() {
		group_ctx = store.group_context_text(s.group, s.name)
		if len(group_ctx) == 0 {
			delete(group_ctx)
			group_ctx = ""
		} else {
			sys_count += 1
		}
	}
	// LID projection: model sees a short structured window; session keeps full fidelity until write-back.
	projected := session_project_messages(s)
	flat := make([dynamic]provider.Message, 0, len(projected) + sys_count + 4)
	if len(s.system_prompt) > 0 {
		append(&flat, provider.Message{role = .System, content = strings.clone(s.system_prompt), cacheable = true})
	}
	if len(group_ctx) > 0 {
		append(&flat, provider.Message{role = .System, content = group_ctx})
	}
	for m in projected {
		append(&flat, m)
	}
	delete(projected)
	// Progressive skills: inject matched bodies into the volatile tail (not system prefix).
	// Lean prompt skips auto skill body injection (load_skill on demand).
	if !agent.prompt_lean_enabled() {
		last_user := ""
		for i := len(s.messages) - 1; i >= 0; i -= 1 {
			if s.messages[i].role == .User {
				last_user = s.messages[i].content
				break
			}
		}
		if len(last_user) > 0 {
			notes := agent.auto_activate_skill_notes(last_user)
			for note in notes {
				append(&flat, provider.Message{role = .User, content = note})
			}
			delete(notes)
		}
	}
	// Clear-then-compact ladder before the model call.
	prep := session_prepare_context(&flat, p)
	if session_writeback_prepare(s, flat[:], prep) {
		prep.writeback = true
	}
	msgs := make([]provider.Message, len(flat))
	copy(msgs, flat[:])
	delete(flat)

	args := new(Job_Args)
	args.session = s
	args.prov = p^
	args.prov.base_url = strings.clone(p.base_url)
	args.prov.api_key = strings.clone(p.api_key)
	args.prov.default_model = strings.clone(p.default_model)
	args.messages = msgs
	args.tools_enabled = s.tools_enabled
	args.reasoning_effort = strings.clone(s.reasoning_effort)
	args.turn_base = len(s.messages)
	args.prep_stats = prep

	status := "waiting for model"
	if s.tools_enabled {
		status = "waiting (agent)"
	}
	session_enqueue(s, Event{kind = .Job_Started, text = strings.clone(status)})
	th := thread.create_and_start_with_data(args, chat_job, nil, .Normal, false)
	if th == nil {
		s.busy = false
		provider.destroy_messages(args.messages)
		delete(args.messages)
		provider.provider_destroy(&args.prov)
		delete(args.reasoning_effort)
		free(args)
		session_enqueue(s, Event{kind = .Error, text = strings.clone("failed to start chat worker")})
		return
	}
	sync.mutex_lock(&s.job_mu)
	s.job_thread = th
	sync.mutex_unlock(&s.job_mu)
}
