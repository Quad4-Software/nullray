// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Turn-start recall: score past entries by prompt token overlap plus the
SEER toolchain signal (a shared tool-call prefix), render a capped
"experience" block for the system prompt, and distill stop lines from
entries whose failed tail matches the current trajectory.
*/

package experience

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "core:sync"

EXP_RECALL_K :: 5
EXP_BLOCK_CHARS :: 800
EXP_ENTRY_CHARS :: 300
EXP_STOP_LINES :: 3
EXP_RECENT_TOOLS :: 24
EXP_DIGEST_HEAD :: 200

@(private)
g_recent_mu: sync.Mutex
// Ordered tool names from the last recorded turn, heap-owned.
@(private)
g_recent: [dynamic]string

// Called by the turn-end recorder so the next prompt build sees the
// current trajectory tail without threading state through the session.
exp_note_tools :: proc(tools: []string) {
	sync.mutex_lock(&g_recent_mu)
	defer sync.mutex_unlock(&g_recent_mu)
	for s in g_recent {
		delete(s, runtime.heap_allocator())
	}
	clear(&g_recent)
	start := 0
	if len(tools) > EXP_RECENT_TOOLS {
		start = len(tools) - EXP_RECENT_TOOLS
	}
	for name in tools[start:] {
		append(&g_recent, strings.clone(name, runtime.heap_allocator()))
	}
}

exp_recent_tools :: proc(allocator := context.allocator) -> []string {
	out := make([dynamic]string, allocator)
	sync.mutex_lock(&g_recent_mu)
	for name in g_recent {
		append(&out, strings.clone(name, allocator))
	}
	sync.mutex_unlock(&g_recent_mu)
	return out[:]
}

// Distinct normalized query tokens present in the entry task.
exp_token_overlap :: proc(query_norm, task_norm: string) -> int {
	tset := make(map[string]bool, context.temp_allocator)
	for tok in strings.fields(task_norm, context.temp_allocator) {
		tset[tok] = true
	}
	seen := make(map[string]bool, context.temp_allocator)
	n := 0
	for tok in strings.fields(query_norm, context.temp_allocator) {
		if seen[tok] {
			continue
		}
		seen[tok] = true
		if tset[tok] {
			n += 1
		}
	}
	return n
}

// Leading tool names the current trajectory shares with the entry.
exp_tool_prefix :: proc(entry_tools, seen: []string) -> int {
	n := min(len(entry_tools), len(seen))
	k := 0
	for k < n && entry_tools[k] == seen[k] {
		k += 1
	}
	return k
}

exp_score :: proc(e: Exp_Entry, query_norm: string, seen: []string) -> int {
	return exp_token_overlap(query_norm, e.task)*2 + exp_tool_prefix(e.tools[:], seen)*3
}

@(private)
Exp_Hit :: struct {
	idx:   int,
	score: int,
}

// Indices of the top-k entries by score, recent wins ties.
exp_top_k :: proc(entries: []Exp_Entry, query: string, seen: []string, k: int, allocator := context.allocator) -> []int {
	q := exp_normalize(query, context.temp_allocator)
	hits := make([dynamic]Exp_Hit, context.temp_allocator)
	for e, i in entries {
		s := exp_score(e, q, seen)
		if s <= 0 {
			continue
		}
		append(&hits, Exp_Hit{idx = i, score = s})
	}
	slice.sort_by(hits[:], proc(a, b: Exp_Hit) -> bool {
		if a.score != b.score {
			return a.score > b.score
		}
		return a.idx > b.idx
	})
	out := make([dynamic]int, allocator)
	for h, i in hits {
		if i >= k {
			break
		}
		append(&out, h.idx)
	}
	return out[:]
}

// Largest k in 2..3 where the last k names of seen equal the last k of
// the entry tail. A repeated tail is what a looped trajectory leaves.
exp_tail_match :: proc(entry_tools, seen: []string) -> int {
	m := min(len(entry_tools), len(seen), 3)
	for k := m; k >= 2; k -= 1 {
		ok := true
		for j in 0 ..< k {
			if seen[len(seen) - k + j] != entry_tools[len(entry_tools) - k + j] {
				ok = false
				break
			}
		}
		if ok {
			return k
		}
	}
	return 0
}

exp_failed :: proc(outcome: string) -> bool {
	return outcome == "looped" || outcome == "err" || outcome == "escalated"
}

// Stop rules: what NOT to repeat when the current tail matches a failed one.
exp_stop_lines :: proc(entries: []Exp_Entry, seen: []string, cap: int, allocator := context.allocator) -> []string {
	out := make([dynamic]string, allocator)
	for e in entries {
		if len(out) >= cap {
			break
		}
		if !exp_failed(e.outcome) {
			continue
		}
		k := exp_tail_match(e.tools[:], seen)
		if k < 2 {
			continue
		}
		seq := strings.join(e.tools[len(e.tools) - k:], "->", context.temp_allocator)
		note := e.note
		if len(note) == 0 {
			note = e.outcome
		}
		append(&out, fmt.aprintf(
			"stop: %s ended %s (%s); do not repeat",
			seq, e.outcome, note,
			allocator = allocator,
		))
	}
	return out[:]
}

// Head of the curated digest, folded into the block when /distill ran.
@(private)
exp_digest_head :: proc(allocator := context.allocator) -> string {
	st := exp_store(context.temp_allocator)
	path, jerr := filepath.join({st.dir, EXP_DIGEST_FILE}, context.temp_allocator)
	if jerr != nil {
		return ""
	}
	data, rerr := os.read_entire_file(path, context.temp_allocator)
	if rerr != nil {
		return ""
	}
	lines := strings.split_lines(string(data), context.temp_allocator)
	start := 0
	if len(lines) > 0 && strings.trim_space(lines[0]) == "---" {
		for j in 1 ..< len(lines) {
			if strings.trim_space(lines[j]) == "---" {
				start = j + 1
				break
			}
		}
	}
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	for k in start ..< len(lines) {
		trimmed := strings.trim_space(lines[k])
		if len(trimmed) == 0 || strings.has_prefix(trimmed, "#") {
			continue
		}
		if strings.builder_len(b) + len(trimmed) + 1 > EXP_DIGEST_HEAD {
			break
		}
		if strings.builder_len(b) > 0 {
			strings.write_byte(&b, ' ')
		}
		strings.write_string(&b, trimmed)
	}
	return strings.clone(strings.to_string(b), allocator)
}

// The "experience" section body for build_system_prompt, "" when off or
// empty. Whole block stays under EXP_BLOCK_CHARS.
exp_prompt_block :: proc(query: string, allocator := context.allocator) -> string {
	if !exp_enabled() {
		return strings.clone("", allocator)
	}
	entries := exp_load_entries(context.temp_allocator)
	defer exp_destroy_entries(&entries, context.temp_allocator)
	if len(entries) == 0 {
		return strings.clone("", allocator)
	}
	seen := exp_recent_tools(context.temp_allocator)
	b: strings.Builder
	strings.builder_init(&b, allocator)
	hits := exp_top_k(entries[:], query, seen, EXP_RECALL_K, context.temp_allocator)
	for idx in hits {
		e := entries[idx]
		seq := strings.join(e.tools[:], "->", context.temp_allocator)
		if len(seq) == 0 {
			seq = "(no tools)"
		}
		line := fmt.aprintf(
			"past: when you ran %s on \"%s\", result was %s: %s\n",
			seq, e.task, e.outcome, e.note,
			allocator = context.temp_allocator,
		)
		if len(line) > EXP_ENTRY_CHARS {
			line = fmt.aprintf("%.*s...\n", EXP_ENTRY_CHARS, line, allocator = context.temp_allocator)
		}
		if strings.builder_len(b) + len(line) > EXP_BLOCK_CHARS {
			break
		}
		strings.write_string(&b, line)
	}
	for sline in exp_stop_lines(entries[:], seen, EXP_STOP_LINES, context.temp_allocator) {
		line := fmt.aprintf("%s\n", sline, allocator = context.temp_allocator)
		if strings.builder_len(b) + len(line) > EXP_BLOCK_CHARS {
			break
		}
		strings.write_string(&b, line)
	}
	if head := exp_digest_head(context.temp_allocator); len(head) > 0 {
		line := fmt.aprintf("digest: %s\n", head, allocator = context.temp_allocator)
		if strings.builder_len(b) + len(line) <= EXP_BLOCK_CHARS {
			strings.write_string(&b, line)
		}
	}
	return strings.to_string(b)
}
