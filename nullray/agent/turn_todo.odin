// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Per-turn todo integration for run_turn: bind the session store for tool
procs on this thread, count the turn for staleness, and inject the open
task block into the last user message of the outbound copy. The block is
lazy: zero cost when the list is empty, and never touches messages[0] so
system-prompt prefix caching stays intact.
*/

package agent

import "core:path/filepath"
import "core:strings"
import "nullray:provider"
import "nullray:subagent"
import "nullray:todo"

Todo_Turn :: struct {
	prev: todo.Bind,
}

turn_todo_begin :: proc(cfg: Config, msgs: ^[dynamic]provider.Message, allocator := context.allocator) -> Todo_Turn {
	sid := cfg.session_id
	read_only := false
	if len(sid) == 0 {
		// Child agent turn: inherit the session bound by the parent worker
		// so subagents read the same list. Writes stay refused via the
		// read_only flag.
		if bpath, _, bok := subagent.session_bind(); bok && len(bpath) > 0 {
			sid = filepath.stem(bpath)
			read_only = true
		}
	}
	t := Todo_Turn{prev = todo.bind(sid, read_only)}
	if !todo.enabled() {
		return t
	}
	todo.mark_turn(sid)
	if todo.take_completed_notice(sid) {
		emit(cfg, .Status, "tasks complete")
	}
	block := todo.prompt_block(sid, context.temp_allocator)
	if len(block) == 0 {
		return t
	}
	for i := len(msgs^) - 1; i >= 0; i -= 1 {
		if msgs[i].role == .User {
			merged := strings.concatenate({msgs[i].content, "\n\n", block}, allocator)
			delete(msgs[i].content)
			msgs[i].content = merged
			break
		}
	}
	return t
}

turn_todo_end :: proc(t: Todo_Turn) {
	todo.unbind(t.prev)
}
