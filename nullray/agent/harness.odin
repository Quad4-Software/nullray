// SPDX-License-Identifier: 0BSD
/*
LID harness helpers: metrics, tool envelopes, artifact offload, prepare ladder.
*/

package agent

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "nullray:constants"
import "nullray:provider"
import "nullray:store"

Harness_Metrics :: struct {
	call_count:             int,
	total_prompt_chars:     int,
	peak_prompt_chars:      int,
	stubbed_bytes:          int,
	retained_tool_bytes:    int,
	artifacts_stored:       int,
	compact_events:         int,
	clear_events:           int,
	writeback_events:       int,
	midturn_prepare_events: int,
	tools_json_chars:       int,
}

Prepare_Stats :: struct {
	cleared:       int,
	compacted:     bool,
	writeback:     bool,
	stubbed_bytes: int,
}

Prepare_Context_Proc :: #type proc(
	msgs: ^[dynamic]provider.Message,
	p: ^provider.Provider,
	user: rawptr,
) -> Prepare_Stats

harness_metrics_enabled :: proc() -> bool {
	if v, ok := os.lookup_env(constants.ENV_HARNESS_METRICS, context.temp_allocator); ok {
		switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
		case "1", "true", "yes", "on":
			return true
		case "0", "false", "no", "off":
			return false
		}
	}
	if v, ok := os.lookup_env(constants.ENV_DEBUG, context.temp_allocator); ok {
		switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
		case "1", "true", "yes", "on":
			return true
		}
	}
	return false
}

lid_enabled :: proc() -> bool {
	if v, ok := os.lookup_env(constants.ENV_LID, context.temp_allocator); ok {
		switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
		case "0", "false", "no", "off", "disable":
			return false
		case "1", "true", "yes", "on":
			return true
		}
	}
	return true
}

prompt_lean_enabled :: proc() -> bool {
	if v, ok := os.lookup_env(constants.ENV_PROMPT, context.temp_allocator); ok {
		switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
		case "lean":
			return true
		case "full":
			return false
		case "auto":
			return print_mode_active()
		}
	}
	return print_mode_active()
}

print_mode_active :: proc() -> bool {
	if v, ok := os.lookup_env(constants.ENV_PRINT, context.temp_allocator); ok {
		switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
		case "1", "true", "yes", "on":
			return true
		}
	}
	return false
}

projection_user_turns :: proc() -> int {
	if v, ok := os.lookup_env(constants.ENV_PROJECTION_TURNS, context.temp_allocator); ok {
		n, n_ok := strconv.parse_int(v)
		if n_ok && n >= 1 {
			return n
		}
	}
	return constants.PROJECTION_USER_TURNS_DEFAULT
}

projection_tool_stubs :: proc() -> int {
	if v, ok := os.lookup_env(constants.ENV_PROJECTION_TOOL_STUBS, context.temp_allocator); ok {
		n, n_ok := strconv.parse_int(v)
		if n_ok && n >= 1 {
			return n
		}
	}
	return constants.PROJECTION_TOOL_STUBS_DEFAULT
}

compact_chars_budget :: proc() -> int {
	if v, ok := os.lookup_env(constants.ENV_COMPACT_CHARS, context.temp_allocator); ok {
		n, n_ok := strconv.parse_int(v)
		if n_ok && n > 4_000 {
			return n
		}
		if n_ok && n == 0 {
			return 0
		}
	}
	return constants.COMPACT_CHARS_DEFAULT
}

tool_clear_keep :: proc() -> int {
	if v, ok := os.lookup_env(constants.ENV_TOOL_CLEAR_KEEP, context.temp_allocator); ok {
		n, n_ok := strconv.parse_int(v)
		if n_ok && n >= 1 {
			return n
		}
	}
	return constants.TOOL_CLEAR_KEEP_DEFAULT
}

messages_content_chars :: proc(msgs: []provider.Message) -> int {
	total := 0
	for m in msgs {
		total += len(m.content) + len(m.reasoning) + len(m.name)
		for tc in m.tool_calls {
			total += len(tc.name) + len(tc.arguments) + len(tc.id)
		}
	}
	return total
}

messages_content_chars_excluding_system :: proc(msgs: []provider.Message) -> int {
	total := 0
	for m in msgs {
		if m.role == .System {
			continue
		}
		total += len(m.content) + len(m.reasoning) + len(m.name)
		for tc in m.tool_calls {
			total += len(tc.name) + len(tc.arguments) + len(tc.id)
		}
	}
	return total
}

is_cleared_tool_content :: proc(content: string) -> bool {
	return strings.has_prefix(content, constants.TOOL_CLEAR_STUB_PREFIX) ||
		strings.contains(content, "artifact=")
}

looks_like_tool_error :: proc(content: string) -> bool {
	lower := strings.to_lower(content, context.temp_allocator)
	if strings.has_prefix(lower, "error") {
		return true
	}
	if strings.contains(lower, "failed:") {
		return true
	}
	if strings.contains(lower, "not allowed") {
		return true
	}
	if strings.contains(lower, "unknown tool") {
		return true
	}
	if strings.contains(lower, "permission_denied") || strings.contains(lower, "permission denied") {
		return true
	}
	if strings.contains(lower, "status=error") {
		return true
	}
	return false
}

excerpt_ends :: proc(body: string, n: int, allocator := context.allocator) -> string {
	if n <= 0 || len(body) <= n {
		return strings.clone(body, allocator)
	}
	half := n / 2
	if half < 1 {
		half = 1
	}
	head := body[:half]
	tail := body[len(body) - (n - half):]
	return fmt.aprintf("%s\n...\n%s", head, tail, allocator = allocator)
}

/*
Schema-normalized tool envelope for isomorphic root observations.
*/
format_tool_envelope :: proc(
	status: string,
	cmd_or_path: string,
	exit_code: int,
	artifact_id: string,
	excerpt: string,
	lines: int,
	allocator := context.allocator,
) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	fmt.sbprintf(&b, "status=%s", status)
	if len(cmd_or_path) > 0 {
		fmt.sbprintf(&b, " path=%s", cmd_or_path)
	}
	if exit_code != 0 || status == "error" {
		fmt.sbprintf(&b, " exit=%d", exit_code)
	}
	if lines > 0 {
		fmt.sbprintf(&b, " lines=%d", lines)
	}
	if len(artifact_id) > 0 {
		fmt.sbprintf(&b, " artifact=%s", artifact_id)
	}
	strings.write_string(&b, "\n--- excerpt ---\n")
	strings.write_string(&b, excerpt)
	return strings.to_string(b)
}

count_lines :: proc(s: string) -> int {
	if len(s) == 0 {
		return 0
	}
	n := 1
	for c in s {
		if c == '\n' {
			n += 1
		}
	}
	return n
}

/*
Offload large tool bodies to the artifact store. Returns provider-facing text.
metrics is updated in place when non-nil.
*/
offload_tool_result :: proc(
	name: string,
	raw: string,
	cmd_or_path: string,
	is_err: bool,
	metrics: ^Harness_Metrics,
	allocator := context.allocator,
) -> string {
	status := "ok"
	exit_code := 0
	if is_err {
		status = "error"
		exit_code = 1
	}
	threshold := store.artifact_chars_threshold()
	lines := count_lines(raw)
	if lid_enabled() && threshold > 0 && len(raw) > threshold {
		id, ok := store.artifact_store(raw)
		if ok {
			if metrics != nil {
				metrics.artifacts_stored += 1
				metrics.stubbed_bytes += len(raw)
			}
			excerpt := excerpt_ends(raw, constants.ARTIFACT_EXCERPT_CHARS, context.temp_allocator)
			out := format_tool_envelope(status, cmd_or_path, exit_code, id, excerpt, lines, allocator)
			delete(id)
			return out
		}
	}
	if metrics != nil {
		metrics.retained_tool_bytes += len(raw)
	}
	excerpt := raw
	if len(excerpt) > constants.ARTIFACT_EXCERPT_CHARS * 4 {
		excerpt = excerpt_ends(raw, constants.ARTIFACT_EXCERPT_CHARS * 2, context.temp_allocator)
		out := format_tool_envelope(status, cmd_or_path, exit_code, "", excerpt, lines, allocator)
		return out
	}
	return format_tool_envelope(status, cmd_or_path, exit_code, "", excerpt, lines, allocator)
}

tool_clear_stub :: proc(m: provider.Message, allocator := context.allocator) -> string {
	name := m.name
	if len(name) == 0 {
		name = "tool"
	}
	if strings.contains(m.content, "artifact=") {
		return strings.clone(m.content, allocator)
	}
	body := m.content
	id := ""
	if lid_enabled() && store.artifact_chars_threshold() > 0 && len(body) > store.artifact_chars_threshold() {
		aid, ok := store.artifact_store(body)
		if ok {
			id = aid
		}
	}
	excerpt := excerpt_ends(body, min(200, constants.ARTIFACT_EXCERPT_CHARS), context.temp_allocator)
	if len(id) > 0 {
		out := fmt.aprintf(
			"%s %s %d bytes artifact=%s]\n--- excerpt ---\n%s",
			constants.TOOL_CLEAR_STUB_PREFIX,
			name,
			len(body),
			id,
			excerpt,
			allocator = allocator,
		)
		delete(id)
		return out
	}
	return fmt.aprintf(
		"%s %s %d bytes; re-call or read_artifact if needed]\n--- excerpt ---\n%s",
		constants.TOOL_CLEAR_STUB_PREFIX,
		name,
		len(body),
		excerpt,
		allocator = allocator,
	)
}

clear_old_tool_results :: proc(msgs: ^[dynamic]provider.Message, keep: int) -> int {
	if msgs == nil || keep < 0 {
		return 0
	}
	tool_idxs := make([dynamic]int, context.temp_allocator)
	for m, i in msgs {
		if m.role == .Tool {
			append(&tool_idxs, i)
		}
	}
	if len(tool_idxs) <= keep {
		return 0
	}
	cleared := 0
	cutoff := len(tool_idxs) - keep
	for ti in 0 ..< cutoff {
		i := tool_idxs[ti]
		m := msgs[i]
		if is_cleared_tool_content(m.content) && strings.has_prefix(m.content, constants.TOOL_CLEAR_STUB_PREFIX) {
			continue
		}
		if looks_like_tool_error(m.content) && !strings.contains(m.content, "artifact=") {
			continue
		}
		if is_cleared_tool_content(m.content) && len(m.content) < constants.ARTIFACT_EXCERPT_CHARS * 2 {
			continue
		}
		stub := tool_clear_stub(m)
		delete(m.content)
		msgs[i].content = stub
		cleared += 1
	}
	return cleared
}

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

	if keep > 2 {
		stats.cleared += clear_old_tool_results(msgs, 2)
		total = messages_content_chars_excluding_system(msgs[:])
		if total <= trigger {
			return stats
		}
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
		"nullray harness: calls=%d mean_chars=%d peak_chars=%d stubbed=%d retained=%d artifacts=%d clear=%d compact=%d writeback=%d midturn=%d tools_json=%d\n",
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
