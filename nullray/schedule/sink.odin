// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Wakeup sink plumbing. The watcher emits each due job through the sink
registered by the host (TUI or serve daemon). Two flavors exist: the
unscoped sink routes to a single bound session, and the scoped sink also
receives the job's session_scope so multi-session hosts can route the
wakeup back to the session that created the job.
*/

package schedule

Due :: struct {
	id:     int,
	tag:    string,
	prompt: string,
	// Snapshot of the job's session_scope at fire time, for scoped sinks
	// (the job itself may already be removed for one-shots).
	scope:  string,
	kind:   Job_Kind,
}

Emit_Proc   :: #type proc(prompt, tag: string)
Queued_Proc :: #type proc(tag: string) -> int
Busy_Proc   :: #type proc() -> bool
// Scoped variants see the session scope the job was created under. When a
// scoped sink is registered it replaces the unscoped one.
Emit_Scoped_Proc   :: #type proc(prompt, tag, scope: string)
Queued_Scoped_Proc :: #type proc(tag, scope: string) -> int

g_emit:          Emit_Proc
g_queued:        Queued_Proc
g_busy:          Busy_Proc
g_emit_scoped:   Emit_Scoped_Proc
g_queued_scoped: Queued_Scoped_Proc

schedule_set_wakeup_sink :: proc(emit: Emit_Proc, queued: Queued_Proc) {
	g_emit = emit
	g_queued = queued
}

// Scoped sink for multi-session hosts (serve). Registration is additive:
// the unscoped sink keeps working for single-session hosts like the TUI.
schedule_set_wakeup_sink_scoped :: proc(emit: Emit_Scoped_Proc, queued: Queued_Scoped_Proc) {
	g_emit_scoped = emit
	g_queued_scoped = queued
}

schedule_set_busy_probe :: proc(busy: Busy_Proc) {
	g_busy = busy
}

@(private)
wakeup_still_queued :: proc(tag, scope: string) -> bool {
	if g_queued_scoped != nil {
		return g_queued_scoped(tag, scope) > 0
	}
	if g_queued == nil {
		return false
	}
	return g_queued(tag) > 0
}

// Emit one due job through the active sink.
@(private)
emit_due :: proc(d: Due) {
	if g_emit_scoped != nil {
		g_emit_scoped(d.prompt, d.tag, d.scope)
	} else if g_emit != nil {
		g_emit(d.prompt, d.tag)
	}
}

due_list_destroy :: proc(due: []Due) {
	for d in due {
		delete(d.tag)
		delete(d.prompt)
		delete(d.scope)
	}
	delete(due)
}
