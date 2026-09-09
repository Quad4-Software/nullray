// SPDX-License-Identifier: 0BSD
/*
Plan-step rewind checkpoints. FS undo stays on existing snapshots.
Leave RAG index as-is; store a short lesson for the next attempt.
*/

package agent

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"
import "nullray:constants"
import "nullray:sandbox"

plan_rewind_dir :: proc(allocator := context.allocator) -> string {
	ws := sandbox.workspace_current()
	if len(ws) == 0 {
		ws = "."
	}
	joined, err := filepath.join({ws, constants.PLAN_REWIND_DIR}, allocator)
	if err != nil {
		return fmt.aprintf("%s/%s", ws, constants.PLAN_REWIND_DIR, allocator = allocator)
	}
	return joined
}

/*
Write a step-boundary checkpoint. lesson may be empty on success advance.
*/
write_plan_rewind_checkpoint :: proc(step_index: int, step_text, lesson: string) -> string {
	dir := plan_rewind_dir(context.temp_allocator)
	if err := os.make_directory_all(dir); err != nil && err != .Exist {
		return fmt.tprintf("plan rewind mkdir failed: %v", err)
	}
	ts := time.time_to_unix(time.now())
	path, _ := filepath.join({dir, fmt.tprintf("step_%d_%d.md", step_index, ts)}, context.temp_allocator)
	body := fmt.tprintf(
		"# plan rewind\n\nstep_index: %d\nstep: %s\nlesson: %s\nnote: restore files with /undo or /checkpoint; do not rewind RAG vectors\n",
		step_index,
		step_text,
		lesson,
	)
	if os.write_entire_file(path, transmute([]u8)body) != nil {
		return "plan rewind write failed"
	}
	return ""
}

format_rewind_note :: proc(step_index: int, step_text, lesson: string, allocator := context.allocator) -> string {
	return fmt.aprintf(
		"[nullray rewind] step %d failed.\nstep: %s\nlesson: %s\nRestore files with /undo if needed, then retry this step. RAG index was not rolled back.\n",
		step_index,
		step_text,
		lesson,
		allocator = allocator,
	)
}
