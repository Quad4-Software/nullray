// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Result-aware loop detection for the agent turn loop. Pure functions on a
small signature history so repeats only count when the tool output repeats
too, plus period-2/period-3 cycle detection. Also holds the malformed tool
call classification and retry budget helpers.
*/

package agent

import "core:fmt"
import "core:hash"
import "core:os"
import "core:strconv"
import "core:strings"
import "nullray:constants"
import "nullray:provider"

// Keep the last few executed call-set observations. Nine entries (cap 8
// plus the incoming sig) cover a period-3 cycle seen three times.
LOOP_HISTORY_CAP :: 9
// Only the head of joined tool results feeds the repeat hash so large tails
// do not cost compare time.
LOOP_RESULT_HEAD_BYTES :: 200
// Distinct signatures warned about in one turn before any repeat warns again.
LOOP_MARK_CAP :: 16

Loop_Entry :: struct {
	sig:         u64,
	result_head: u64,
}

Loop_History :: struct {
	entries: [LOOP_HISTORY_CAP]Loop_Entry,
	len:     int,
}

Loop_Verdict :: enum {
	None,
	Identical,
	Cycle,
}

Loop_Marks :: struct {
	sigs: [LOOP_MARK_CAP]u64,
	len:  int,
}

Malformed_Kind :: enum {
	None,
	Unknown_Tool,
	Not_Runnable,
	Bad_Args_Json,
	Args_Not_Object,
}

loop_history_push :: proc(h: ^Loop_History, e: Loop_Entry) {
	if h == nil {
		return
	}
	if h.len < LOOP_HISTORY_CAP {
		h.entries[h.len] = e
		h.len += 1
		return
	}
	for i in 0 ..< LOOP_HISTORY_CAP - 1 {
		h.entries[i] = h.entries[i + 1]
	}
	h.entries[LOOP_HISTORY_CAP - 1] = e
}

// Hash name+args for every call in the set with separators so
// ("ab","c") never collides with ("a","bc").
loop_sig_of_calls :: proc(calls: []provider.Tool_Call) -> u64 {
	h := u64(0xcbf29ce484222325)
	sep0 := "\x00"
	sep1 := "\x01"
	for c in calls {
		h = hash.fnv64a(transmute([]byte)c.name, h)
		h = hash.fnv64a(transmute([]byte)sep0, h)
		h = hash.fnv64a(transmute([]byte)c.arguments, h)
		h = hash.fnv64a(transmute([]byte)sep1, h)
	}
	return h
}

// Fold the head of a tool result into a rolling result hash. left is the
// remaining byte budget shared across the whole call set.
loop_result_head_update :: proc(h: u64, text: string, left: ^int) -> u64 {
	if left == nil || left^ <= 0 {
		return h
	}
	n := min(len(text), left^)
	out := hash.fnv64a(transmute([]byte)text[:n], h)
	left^ -= n
	// Boundary byte so ("ab","c") and ("a","bc") differ.
	sep := "\x02"
	return hash.fnv64a(transmute([]byte)sep, out)
}

/*
Decide whether an incoming call-set signature repeats a loop. entries are
the recorded history of executed sets (sig + result head), sig is the new
set not yet run. Returns the verdict and, for .Cycle, the period length.

Identical repeat: the tail of the history is a run of the same signature
with the same result head, and this call extends it past the threshold.
A poller that gets different output each time breaks the run and never
trips.

Cycle: the last 3*period signatures of the extended sequence repeat, for
period 2 or 3 (A,B,A,B,A,B or A,B,C,A,B,C,A,B,C). Two periods is too cheap:
a legit test-read-edit rhythm trips it, so a cycle needs three full repeats.
*/
loop_check :: proc(entries: []Loop_Entry, sig: u64) -> (verdict: Loop_Verdict, period: int) {
	// Identical streak: count the trailing run of (sig, same result head).
	run := 0
	rh := u64(0)
	for i := len(entries) - 1; i >= 0; i -= 1 {
		e := entries[i]
		if e.sig != sig {
			break
		}
		if run == 0 {
			rh = e.result_head
		} else if e.result_head != rh {
			break
		}
		run += 1
	}
	if run + 1 >= constants.MAX_IDENTICAL_TOOL_LOOPS && run > 0 {
		return .Identical, 0
	}
	// Cycle detection on the signature sequence extended by the new call.
	// Sequence index len(entries) maps to the incoming sig. A cycle needs
	// three full periods of evidence (3*p signatures), not two.
	total := len(entries) + 1
	periods := [2]int{2, 3}
	for p in periods {
		if total < 3 * p {
			continue
		}
		match := true
		for k in 0 ..< p {
			ia := total - 3*p + k
			ib := total - 2*p + k
			ic := total - p + k
			a := entries[ia].sig if ia < len(entries) else sig
			b := entries[ib].sig if ib < len(entries) else sig
			c := entries[ic].sig if ic < len(entries) else sig
			if a != b || b != c {
				match = false
				break
			}
		}
		if !match {
			continue
		}
		// A window of one repeated signature is the identical case above,
		// not a cycle, and a poller must stay result-aware.
		all_same := true
		first_i := total - 3*p
		first := entries[first_i].sig if first_i < len(entries) else sig
		for k in 1 ..< 3 * p {
			ia := total - 3*p + k
			a := entries[ia].sig if ia < len(entries) else sig
			if a != first {
				all_same = false
				break
			}
		}
		if !all_same {
			return .Cycle, p
		}
	}
	return .None, 0
}

loop_marks_has :: proc(m: ^Loop_Marks, sig: u64) -> bool {
	if m == nil {
		return false
	}
	for i in 0 ..< m.len {
		if m.sigs[i] == sig {
			return true
		}
	}
	return false
}

loop_marks_add :: proc(m: ^Loop_Marks, sig: u64) {
	if m == nil || loop_marks_has(m, sig) {
		return
	}
	if m.len >= LOOP_MARK_CAP {
		// Full: evict the oldest mark so a fresh signature still gets
		// recorded instead of the table silently freezing.
		for i in 0 ..< LOOP_MARK_CAP - 1 {
			m.sigs[i] = m.sigs[i + 1]
		}
		m.sigs[LOOP_MARK_CAP - 1] = sig
		return
	}
	m.sigs[m.len] = sig
	m.len += 1
}

// For a cycle trip, mark every signature in the repeating window so any
// member arriving again counts as post-intervene.
loop_marks_add_cycle :: proc(m: ^Loop_Marks, entries: []Loop_Entry, incoming: u64, period: int) {
	total := len(entries) + 1
	for k in 0 ..< period {
		i := total - period + k
		if i < len(entries) {
			loop_marks_add(m, entries[i].sig)
		} else {
			loop_marks_add(m, incoming)
		}
	}
}

// Distinct tool names in a call set, for the intervene nudge text.
loop_call_names :: proc(calls: []provider.Tool_Call, allocator := context.temp_allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	for c, i in calls {
		seen := false
		for j in 0 ..< i {
			if calls[j].name == c.name {
				seen = true
				break
			}
		}
		if seen {
			continue
		}
		if strings.builder_len(b) > 0 {
			strings.write_string(&b, ", ")
		}
		strings.write_string(&b, c.name)
	}
	return strings.to_string(b)
}

/*
Per-step anti-loop gate. Checks the incoming call set against the executed
history. Stage 1 marks the signature(s) and asks for an intervene nudge,
stage 2 stops the turn when a marked signature repeats. The stop result
owns the appended assistant message, the caller returns it as-is.
*/
turn_loop_gate :: proc(
	msgs: ^[dynamic]provider.Message,
	hist: ^Loop_History,
	marks: ^Loop_Marks,
	calls: []provider.Tool_Call,
	sig: u64,
	res: ^provider.Chat_Response,
	text_calls: bool,
	cfg: Config,
	usage: provider.Usage,
	harness: Harness_Metrics,
	allocator := context.allocator,
) -> (stop: bool, intervene: bool, out: Run_Result) {
	if hist == nil || marks == nil || res == nil {
		return false, false, out
	}
	verdict, period := loop_check(hist.entries[:hist.len], sig)
	if verdict == .None {
		return false, false, out
	}
	if loop_marks_has(marks, sig) {
		delete(res.content)
		delete(res.reasoning)
		delete(res.model)
		delete(res.err)
		delete(res.finish_reason)
		if text_calls {
			provider.destroy_tool_calls_owned(calls)
		} else {
			provider.destroy_tool_calls_owned(res.tool_calls)
		}
		msg := strings.clone(
			"Stopped: repeated the same tool calls after a loop warning. Adjust the approach or /continue with new instructions.",
			allocator,
		)
		emit(cfg, .Status, "anti-loop: repeated tools after intervene")
		append(msgs, provider.Message{role = .Assistant, content = msg})
		return true, false, Run_Result{
			ok = true,
			messages = msgs^,
			content = msg,
			stopped = owned_stop("loop", allocator),
			usage = usage,
			harness = harness,
		}
	}
	loop_marks_add(marks, sig)
	if verdict == .Cycle && period > 0 {
		loop_marks_add_cycle(marks, hist.entries[:hist.len], sig, period)
	}
	emit(cfg, .Status, "anti-loop: intervene")
	return false, true, out
}

/*
Call-formation failures only. Permission denials, mode and gate blocks,
hook blocks, and normal tool errors stay out so the retry budget cannot be
burned by legitimate refusals.
*/
malformed_call_class :: proc(tool_err: string) -> Malformed_Kind {
	if len(tool_err) == 0 {
		return .None
	}
	if strings.has_prefix(tool_err, "unknown tool") {
		return .Unknown_Tool
	}
	if strings.has_prefix(tool_err, "tool not runnable") {
		return .Not_Runnable
	}
	if strings.has_prefix(tool_err, "bad tool args JSON") {
		return .Bad_Args_Json
	}
	if strings.has_prefix(tool_err, "tool args must be a JSON object") {
		return .Args_Not_Object
	}
	return .None
}

malformed_kind_name :: proc(kind: Malformed_Kind) -> string {
	switch kind {
	case .Unknown_Tool:
		return "unknown tool"
	case .Not_Runnable:
		return "tool not runnable"
	case .Bad_Args_Json:
		return "invalid args JSON"
	case .Args_Not_Object:
		return "args not a JSON object"
	case .None:
	}
	return "malformed call"
}

// Per-turn malformed-call retry budget from NULLRAY_TOOL_RETRY, clamped.
tool_retry_budget :: proc() -> int {
	budget := constants.TOOL_RETRY_DEFAULT
	if v, ok := os.lookup_env(constants.ENV_TOOL_RETRY, context.temp_allocator); ok {
		if n, nok := strconv.parse_int(strings.trim_space(v)); nok {
			budget = n
		}
	}
	if budget < 0 {
		budget = 0
	}
	if budget > constants.TOOL_RETRY_MAX {
		budget = constants.TOOL_RETRY_MAX
	}
	return budget
}

/*
Tool-result text for a malformed call. While budget remains the model is
told to retry with corrected JSON, once exhausted it is told to answer
without further tool calls.
*/
malformed_result_text :: proc(kind: Malformed_Kind, err: string, retry_left: bool, allocator := context.allocator) -> string {
	if retry_left {
		return fmt.aprintf(
			"Malformed tool call (%s): %s. Fix the call and retry with corrected JSON arguments.",
			malformed_kind_name(kind),
			err,
			allocator = allocator,
		)
	}
	return fmt.aprintf(
		"Malformed tool call (%s): %s. Retry budget exhausted. Answer without further tool calls or explain why you cannot proceed.",
		malformed_kind_name(kind),
		err,
		allocator = allocator,
	)
}
