// SPDX-License-Identifier: 0BSD
/*
LID context prepare ladder and harness metrics logging.
*/

package agent

import "core:fmt"
import "core:strings"
import "nullray:constants"
import "nullray:provider"

/*
Clear-then-compact ladder for a flat message list about to be sent.
*/
prepare_context :: proc(msgs: ^[dynamic]provider.Message, p: ^provider.Provider) -> Prepare_Stats {
	stats: Prepare_Stats
	if msgs == nil {
		return stats
	}
	budget := compact_chars_budget()
	if budget <= 0 {
		return stats
	}
	keep := tool_clear_keep()
	stats.cleared = clear_old_tool_results(msgs, keep)

	total := messages_content_chars_excluding_system(msgs[:])
	trigger := (budget * 70) / 100
	if trigger < 8_000 {
		trigger = budget
	}
	if total <= trigger {
		return stats
	}

	// Lean compact input: stub more aggressively so the summarizer does not
	// ingest full hostile tool bodies.
	stats.cleared += clear_old_tool_results(msgs, 2)
	total = messages_content_chars_excluding_system(msgs[:])
	if total <= trigger {
		return stats
	}

	if p == nil || p.chat == nil || len(msgs) < 6 {
		return stats
	}
	keep_n := constants.COMPACT_KEEP_MESSAGES
	if keep_n >= len(msgs) {
		return stats
	}
	drop_end := len(msgs) - keep_n
	if drop_end <= 1 {
		return stats
	}
	start := 0
	if msgs[0].role == .System {
		start = 1
	}
	if start >= drop_end {
		return stats
	}

	to_summarize := msgs[start:drop_end]
	summary, ok := compact_with_model(p, to_summarize)
	if !ok {
		return stats
	}
	kept_sys: [dynamic]provider.Message
	if start > 0 {
		append(&kept_sys, msgs[0])
	}
	kept_tail := make([dynamic]provider.Message, 0, keep_n, context.temp_allocator)
	for i in drop_end ..< len(msgs) {
		append(&kept_tail, msgs[i])
	}
	for i in start ..< drop_end {
		provider.destroy_message(msgs[i])
	}
	clear(msgs)
	for m in kept_sys {
		append(msgs, m)
	}
	append(msgs, provider.Message{
		role = .User,
		content = fmt.aprintf("Conversation summary (auto-compacted):\n%s", summary),
	})
	delete(summary)
	for m in kept_tail {
		append(msgs, m)
	}
	stats.compacted = true
	return stats
}

harness_record_call :: proc(m: ^Harness_Metrics, prompt_chars: int) {
	if m == nil {
		return
	}
	m.call_count += 1
	m.total_prompt_chars += prompt_chars
	if prompt_chars > m.peak_prompt_chars {
		m.peak_prompt_chars = prompt_chars
	}
}

harness_log_metrics :: proc(m: Harness_Metrics) {
	if !harness_metrics_enabled() {
		return
	}
	mean := 0
	if m.call_count > 0 {
		mean = m.total_prompt_chars / m.call_count
	}
	fmt.eprintf(
		"nullray harness: calls=%d mean_chars=%d peak_chars=%d stubbed=%d retained=%d artifacts=%d clear=%d compact=%d writeback=%d midturn=%d tools_json=%d spec_hit=%d spec_miss=%d spec_submit=%d spec_saved_ms=%d\n",
		m.call_count,
		mean,
		m.peak_prompt_chars,
		m.stubbed_bytes,
		m.retained_tool_bytes,
		m.artifacts_stored,
		m.clear_events,
		m.compact_events,
		m.writeback_events,
		m.midturn_prepare_events,
		m.tools_json_chars,
		m.speculate_hit,
		m.speculate_miss,
		m.speculate_submit,
		m.speculate_saved_ms,
	)
}

cmd_or_path_from_args :: proc(name, args_json: string) -> string {
	key := "path"
	switch name {
	case "run_shell", "run_script", "verify":
		key = "command"
	case "grep_files", "glob_files":
		key = "pattern"
	case "load_skill", "read_artifact", "grep_artifact":
		key = "id"
	}
	// lightweight extract without tools package import cycle risk
	needle := fmt.tprintf(`"%s"`, key)
	idx := strings.index(args_json, needle)
	if idx < 0 {
		return name
	}
	rest := args_json[idx + len(needle):]
	colon := strings.index_byte(rest, ':')
	if colon < 0 {
		return name
	}
	rest = strings.trim_left_space(rest[colon + 1:])
	if len(rest) == 0 || rest[0] != '"' {
		return name
	}
	rest = rest[1:]
	end := strings.index_byte(rest, '"')
	if end < 0 {
		return name
	}
	val := rest[:end]
	if len(val) > 120 {
		return val[:120]
	}
	return val
}
