// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Verify-fail traces and gated skill drafts under .nullray/traces.
*/

package store

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"
import "nullray:constants"
import "nullray:sandbox"

traces_dir :: proc(allocator := context.allocator) -> string {
	ws := sandbox.workspace_current()
	if len(ws) == 0 {
		ws = "."
	}
	joined, err := filepath.join({ws, constants.TRACES_DIR}, allocator)
	if err != nil {
		return fmt.aprintf("%s/%s", ws, constants.TRACES_DIR, allocator = allocator)
	}
	return joined
}

ensure_traces_dir :: proc() -> bool {
	dir := traces_dir(context.temp_allocator)
	_ = sandbox.mkdir_all(dir)
	return true
}

// Classify a failing verify run into a coarse TRAIL-style bucket so evals
// and skill drafts can count failure classes instead of vibes.
trace_classify :: proc(output: string) -> string {
	l := strings.to_lower(output, context.temp_allocator)
	if strings.contains(l, "command not found") ||
	   strings.contains(l, "no such file or directory") ||
	   strings.contains(l, "permission denied") ||
	   strings.contains(l, "not installed") {
		return "execution.environment"
	}
	if strings.contains(l, "timed out") || strings.contains(l, "timeout") ||
	   strings.contains(l, "deadline exceeded") {
		return "execution.timeout"
	}
	if strings.contains(l, "segfault") || strings.contains(l, "panic") ||
	   strings.contains(l, "assertion failed") || strings.contains(l, "sigsegv") {
		return "execution.crash"
	}
	if strings.contains(l, "syntax error") || strings.contains(l, "compile") ||
	   strings.contains(l, "undeclared name") || strings.contains(l, "type mismatch") {
		return "execution.build"
	}
	if strings.contains(l, "assert") || strings.contains(l, "expected") ||
	   strings.contains(l, "failed") || strings.contains(l, " fail") {
		return "verify.test_failure"
	}
	return "verify.failure"
}

/*
Write a redacted verify-fail trace and an optional skill draft for human review.
Returns owned path to the trace file.
*/
trace_store_verify_fail :: proc(
	cmd: string,
	output: string,
	fail_n: int,
	allocator := context.allocator,
) -> string {
	ensure_traces_dir()
	ts := time.time_to_unix(time.now())
	id := fmt.tprintf("verify_%d_%d", ts, fail_n)
	dir := traces_dir(context.temp_allocator)
	trace_path, _ := filepath.join({dir, fmt.tprintf("%s.md", id)}, context.temp_allocator)
	redacted := sandbox.redact_secrets(output, context.temp_allocator)
	if len(redacted) > 8000 {
		redacted = redacted[:8000]
	}
	body := fmt.tprintf(
		"# verify fail\n\ncommand: %s\nfail: %d\ncategory: %s\n\n## output\n\n%s\n",
		cmd,
		fail_n,
		trace_classify(output),
		redacted,
	)
	_ = os.write_entire_file(trace_path, transmute([]u8)body)

	draft_dir, _ := filepath.join({dir, fmt.tprintf("%s_skill_draft", id)}, context.temp_allocator)
	_ = sandbox.mkdir_all(draft_dir)
	skill_path, _ := filepath.join({draft_dir, "SKILL.md"}, context.temp_allocator)
	skill := fmt.tprintf(
		"---\nname: verify-repair-%d\ndescription: Draft from verify fail. Review before install.\n---\n\n# Verify repair draft\n\nCommand that failed: %s\n\n## Suggested rule\n\nAfter edits, run the project Verify command and fix reported path:line findings before claiming done.\n\n## Excerpt\n\n%s\n",
		fail_n,
		cmd,
		redacted,
	)
	_ = os.write_entire_file(skill_path, transmute([]u8)skill)
	return strings.clone(trace_path, allocator)
}
