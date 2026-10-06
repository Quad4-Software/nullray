// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Per-child review sections for verify_all: worktree diff or file heads.
*/

package subagent

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "nullray:constants"
import "nullray:sandbox"


/*
One CHILD review section: task, summary, touched files, and either the
worktree diff or small file heads for shared-isolation children.
*/
verify_child_section :: proc(b: ^strings.Builder, h: Agent_Handle, repo_root: string, detailed: bool, allocator := context.temp_allocator) {
	fmt.sbprintf(b, "=== CHILD %s | role=%s | status=%s | isolation=%s ===\n", h.id, h.role, status_string(h.status), isolation_string(h.isolation))
	if len(h.progress) > 0 {
		fmt.sbprintf(b, "task: %s\n", h.progress)
	}
	if len(h.result_summary) > 0 {
		sum := h.result_summary
		if len(sum) > constants.MAX_CHILD_RESULT_CHARS {
			sum = sum[:constants.MAX_CHILD_RESULT_CHARS]
		}
		fmt.sbprintf(b, "result:\n%s\n", sum)
	}
	if len(h.files_touched) > 0 {
		strings.write_string(b, "files_touched:")
		for f in h.files_touched {
			fmt.sbprintf(b, " %s", f)
		}
		strings.write_byte(b, '\n')
	}
	if h.isolation == .Worktree && len(h.worktree_branch) > 0 {
		if !detailed {
			strings.write_string(b, "(summary only; diff not reviewed)\n")
			return
		}
		diff, derr := worktree_review_diff(repo_root, h.worktree_path, h.worktree_branch, constants.VERIFY_DIFF_MAX_CHARS, allocator)
		if len(derr) > 0 {
			fmt.sbprintf(b, "diff unavailable (%s); review summary only\n", derr)
			return
		}
		if len(strings.trim_space(diff)) == 0 {
			strings.write_string(b, "diff: (no changes)\n")
			return
		}
		safe := sandbox.redact_secrets(diff, allocator)
		fmt.sbprintf(b, "diff vs merge-base (branch %s):\n%s\n", h.worktree_branch, safe)
	} else if detailed {
		verify_append_file_heads(b, h, allocator)
	}
}

verify_append_file_heads :: proc(b: ^strings.Builder, h: Agent_Handle, allocator := context.temp_allocator) {
	n := 0
	for f in h.files_touched {
		if n >= VERIFY_FILE_HEADS_MAX {
			break
		}
		head := verify_file_head(h, f, allocator)
		if len(head) == 0 {
			continue
		}
		safe := sandbox.redact_secrets(head, allocator)
		fmt.sbprintf(b, "--- file head: %s ---\n%s\n", f, safe)
		n += 1
	}
}

verify_file_head :: proc(h: Agent_Handle, rel: string, allocator := context.temp_allocator) -> string {
	path := rel
	if !filepath.is_abs(path) {
		root := len(h.workspace_root) > 0 ? h.workspace_root : workspace_dir(allocator)
		path, _ = filepath.join({root, path}, allocator)
	}
	fd, oerr := os.open(path)
	if oerr != nil {
		return ""
	}
	defer os.close(fd)
	buf := make([]byte, VERIFY_FILE_HEAD_BYTES, context.temp_allocator)
	nr, _ := os.read(fd, buf)
	if nr <= 0 {
		return ""
	}
	return string(buf[:nr])
}

