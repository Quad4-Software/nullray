// SPDX-License-Identifier: 0BSD
/*
LID tool result envelopes and artifact offload.
*/

package agent

import "core:fmt"
import "core:strings"
import "nullray:constants"
import "nullray:provider"
import "nullray:rag"
import "nullray:sandbox"
import "nullray:store"

REDACTED_EXCERPT :: "[redacted excerpt; use grep_artifact/read_artifact]"

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
Replace control chars and newlines so envelope headers stay single-line.
*/
envelope_sanitize_field :: proc(s: string, allocator := context.temp_allocator) -> string {
	if len(s) == 0 {
		return ""
	}
	b: strings.Builder
	strings.builder_init(&b, allocator)
	for i in 0 ..< len(s) {
		c := s[i]
		if c == '\r' || c == '\n' || c == '\t' || c < 0x20 {
			strings.write_byte(&b, ' ')
			continue
		}
		strings.write_byte(&b, c)
	}
	return strings.to_string(b)
}

excerpt_for_envelope :: proc(body: string, n: int, allocator := context.allocator) -> string {
	ex := excerpt_ends(body, n, context.temp_allocator)
	if sandbox.value_looks_secret(ex) || excerpt_has_secret_token(ex) {
		return strings.clone(REDACTED_EXCERPT, allocator)
	}
	tok := sandbox.redact_secret_tokens(ex, allocator)
	if strings.contains(tok, sandbox.REDACTED_SECRET) {
		delete(tok)
		return strings.clone(REDACTED_EXCERPT, allocator)
	}
	return tok
}

@(private)
excerpt_has_secret_token :: proc(ex: string) -> bool {
	lower := strings.to_lower(ex, context.temp_allocator)
	needles := []string{"sk-", "ghp_", "github_pat_", "xoxb-", "xoxp-", "-----begin private key-----"}
	for n in needles {
		if strings.contains(lower, n) {
			return true
		}
	}
	return false
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
	st := envelope_sanitize_field(status)
	path := envelope_sanitize_field(cmd_or_path)
	aid := envelope_sanitize_field(artifact_id)
	b: strings.Builder
	strings.builder_init(&b, allocator)
	fmt.sbprintf(&b, "status=%s", st)
	if len(path) > 0 {
		fmt.sbprintf(&b, " path=%s", path)
	}
	if exit_code != 0 || st == "error" {
		fmt.sbprintf(&b, " exit=%d", exit_code)
	}
	if lines > 0 {
		fmt.sbprintf(&b, " lines=%d", lines)
	}
	if len(aid) > 0 {
		fmt.sbprintf(&b, " artifact=%s", aid)
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
	_ = name
	status := "ok"
	exit_code := 0
	if is_err {
		status = "error"
		exit_code = 1
	}
	detail := sandbox.redact_secrets(cmd_or_path, context.temp_allocator)
	threshold := store.artifact_chars_threshold()
	lines := count_lines(raw)
	if lid_enabled() && threshold > 0 && len(raw) > threshold {
		id, ok := store.artifact_store(raw)
		if ok {
			if metrics != nil {
				metrics.artifacts_stored += 1
				metrics.stubbed_bytes += len(raw)
			}
			_ = rag.Index_Artifact(id, raw)
			excerpt := excerpt_for_envelope(raw, constants.ARTIFACT_EXCERPT_CHARS, context.temp_allocator)
			out := format_tool_envelope(status, detail, exit_code, id, excerpt, lines, allocator)
			delete(id)
			return out
		}
	}
	if metrics != nil {
		metrics.retained_tool_bytes += len(raw)
	}
	if len(raw) > constants.ARTIFACT_EXCERPT_CHARS * 4 {
		excerpt := excerpt_for_envelope(raw, constants.ARTIFACT_EXCERPT_CHARS * 2, context.temp_allocator)
		return format_tool_envelope(status, detail, exit_code, "", excerpt, lines, allocator)
	}
	excerpt := raw
	if sandbox.value_looks_secret(excerpt) {
		excerpt = REDACTED_EXCERPT
	}
	return format_tool_envelope(status, detail, exit_code, "", excerpt, lines, allocator)
}

tool_clear_stub :: proc(m: provider.Message, allocator := context.allocator) -> string {
	name := m.name
	if len(name) == 0 {
		name = "tool"
	}
	// Already offloaded or enveloped: do not re-store framed bodies.
	if strings.contains(m.content, "artifact=") ||
	   strings.contains(m.content, "--- excerpt ---") ||
	   strings.has_prefix(m.content, "status=") {
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
	excerpt := excerpt_for_envelope(body, min(200, constants.ARTIFACT_EXCERPT_CHARS), context.temp_allocator)
	if len(id) > 0 {
		out := fmt.aprintf(
			"%s %s %d bytes artifact=%s]\n--- excerpt ---\n%s",
			constants.TOOL_CLEAR_STUB_PREFIX,
			envelope_sanitize_field(name),
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
		envelope_sanitize_field(name),
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
