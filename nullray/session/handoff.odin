// SPDX-License-Identifier: 0BSD
/*
Write .nullray/HANDOFF.md after compaction.
*/

package session

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "nullray:constants"
import "nullray:sandbox"

session_write_handoff :: proc(s: ^Session, summary: string = "") {
	if s == nil {
		return
	}
	ws := sandbox.workspace_current()
	if len(ws) == 0 {
		ws = "."
	}
	path, _ := filepath.join({ws, constants.HANDOFF_FILE}, context.temp_allocator)
	dir := filepath.dir(path)
	_ = os.make_directory_all(dir)

	goal := ""
	if len(s.plan_body) > 0 {
		goal = s.plan_body
		if len(goal) > 400 {
			goal = goal[:400]
		}
	}
	open := ""
	if len(s.plan_steps) > 0 && s.plan_step_index < len(s.plan_steps) {
		open = s.plan_steps[s.plan_step_index]
	}
	done := ""
	if len(summary) > 0 {
		done = summary
		if len(done) > 1200 {
			done = done[:1200]
		}
	} else if len(s.messages) > 0 {
		last := s.messages[len(s.messages) - 1]
		done = last.content
		if len(done) > 800 {
			done = done[:800]
		}
	}
	verify := "(project Verify / make test)"
	if len(s.plan_verify) > 0 {
		verify = s.plan_verify
		if len(verify) > 400 {
			verify = verify[:400]
		}
	}
	body := fmt.tprintf(
		"# Handoff\n\n## Goal\n\n%s\n\n## Done\n\n%s\n\n## Open\n\n%s\n\n## Cites\n\n(see locate CITES / plan steps)\n\n## Verify\n\n%s\n",
		goal,
		done,
		open,
		verify,
	)
	_ = os.write_entire_file(path, transmute([]u8)body)
}
