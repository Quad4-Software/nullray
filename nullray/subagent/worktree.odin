// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Git worktree isolation for edit subagents. Never uses git stash.
*/

package subagent

import "core:fmt"
import "core:io"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"
import "nullray:constants"
import "nullray:sandbox"

Worktree_Info :: struct {
	path:   string,
	branch: string,
	ok:     bool,
	err:    string,
}

// Per-call drain budget: pipe_has_data loops can be kept alive forever by a
// flooding writer, so a drain returns after this many bytes and lets the
// outer loop re-check the timeout.
@(private)
RUN_CMD_DRAIN_BUDGET :: 64 * 1024

/*
Bounded non-blocking drain for the post-exit path: the child is dead so its
bytes are already kernel-buffered, but a detached grandchild may still hold
the write end open. Read only what pipe_has_data reports ready so a
surviving writer cannot wedge us on a blocking read.
*/
@(private)
run_cmd_drain :: proc(r: ^os.File, b: ^[dynamic]byte, buf: []u8) {
	left := RUN_CMD_DRAIN_BUDGET
	for left > 0 {
		has_data, _ := os.pipe_has_data(r)
		if !has_data {
			return
		}
		n, rerr := os.read(r, buf)
		if n > 0 {
			left -= n
			append(b, ..buf[:n])
		}
		if n == 0 || rerr == io.Error.EOF || rerr == os.General_Error.Broken_Pipe {
			return
		}
	}
}

worktree_base_ref :: proc(allocator := context.temp_allocator) -> string {
	if v, ok := os.lookup_env(constants.ENV_WORKTREE_BASE, allocator); ok && len(v) > 0 {
		return v
	}
	return "HEAD"
}

is_git_repo :: proc(root: string) -> bool {
	git_dir, _ := filepath.join({root, ".git"}, context.temp_allocator)
	return os.is_dir(git_dir) || os.exists(git_dir)
}

run_cmd :: proc(argv: []string, cwd: string, allocator := context.allocator) -> (out: string, err: string) {
	stdout_r, stdout_w, pipe_err := os.pipe()
	if pipe_err != nil {
		return "", fmt.aprintf("pipe failed: %v", pipe_err, allocator = allocator)
	}
	defer os.close(stdout_r)
	stderr_r, stderr_w, pipe_err2 := os.pipe()
	if pipe_err2 != nil {
		return "", fmt.aprintf("pipe failed: %v", pipe_err2, allocator = allocator)
	}
	defer os.close(stderr_r)

	process: os.Process
	{
		defer os.close(stdout_w)
		defer os.close(stderr_w)
		desc := os.Process_Desc{
			working_dir = cwd,
			command = argv,
			stdout = stdout_w,
			stderr = stderr_w,
		}
		start_err: os.Error
		process, start_err = os.process_start(desc)
		if start_err != nil {
			return "", fmt.aprintf("exec failed: %v", start_err, allocator = allocator)
		}
	}
	sub_claim_process_group(process)

	stdout_b: [dynamic]byte
	stdout_b.allocator = context.temp_allocator
	stderr_b: [dynamic]byte
	stderr_b.allocator = context.temp_allocator
	buf: [1024]u8
	timeout := time.Millisecond * 30_000
	start := time.now()
	stdout_done := false
	state: os.Process_State
	stderr_done := false

	for !stdout_done || !stderr_done {
		if time.since(start) >= timeout {
			sub_kill_process_tree(process)
			break
		}
		got_data := false
		if !stdout_done {
			has_data, _ := os.pipe_has_data(stdout_r)
			if has_data {
				n, rerr := os.read(stdout_r, buf[:])
				if n > 0 {
					got_data = true
					append(&stdout_b, ..buf[:n])
				}
				if rerr == io.Error.EOF || rerr == os.General_Error.Broken_Pipe {
					stdout_done = true
				}
			}
		}
		if !stderr_done {
			has_data, _ := os.pipe_has_data(stderr_r)
			if has_data {
				n, rerr := os.read(stderr_r, buf[:])
				if n > 0 {
					got_data = true
					append(&stderr_b, ..buf[:n])
				}
				if rerr == io.Error.EOF || rerr == os.General_Error.Broken_Pipe {
					stderr_done = true
				}
			}
		}
		wait_state, wait_err := os.process_wait(process, 0)
		if wait_err == nil && wait_state.exited {
			state = wait_state
			// Child exited, drain only what is already buffered. A detached
			// grandchild holding a write end must not turn this into a
			// blocking read past the timeout.
			run_cmd_drain(stdout_r, &stdout_b, buf[:])
			run_cmd_drain(stderr_r, &stderr_b, buf[:])
			break
		}
		if !got_data {
			// Quiet child: avoid a busy spin on poll+waitid.
			time.sleep(2 * time.Millisecond)
		}
	}

	if !state.exited {
		// The timeout path already fired the kill, a pipes-EOF exit with
		// the child still running leaves a blocking wait unbounded. Kill
		// the tree first so the wait is bounded either way.
		sub_kill_process_tree(process)
		state, _ = os.process_wait(process)
	}
	combined := fmt.aprintf("%s%s", string(stdout_b[:]), string(stderr_b[:]), allocator = allocator)
	if !state.exited {
		// Fail closed: no real status was captured.
		return combined, strings.clone("process status unavailable", allocator)
	}
	if state.exit_code != 0 {
		return combined, fmt.aprintf("exit %d", state.exit_code, allocator = allocator)
	}
	return combined, ""
}

worktree_create :: proc(
	agent_id: string,
	repo_root: string,
	allocator := context.allocator,
) -> Worktree_Info {
	info := Worktree_Info{}
	if !is_git_repo(repo_root) {
		info.err = strings.clone("not a git repository (worktree unavailable)", allocator)
		return info
	}
	base := worktree_base_ref()
	branch := fmt.aprintf("nullray/%s", agent_id, allocator = allocator)
	wt_root, _ := filepath.join({repo_root, constants.WORKTREES_DIR, agent_id}, allocator)
	wt_parent, _ := filepath.join({repo_root, constants.WORKTREES_DIR}, context.temp_allocator)
	_ = sandbox.mkdir_all(wt_parent)

	argv := []string{"git", "worktree", "add", "-b", branch, wt_root, base}
	out, err := run_cmd(argv, repo_root, context.temp_allocator)
	if len(err) > 0 || strings.contains(out, "fatal:") {
		delete(branch)
		branch = fmt.aprintf("nullray/%s-%d", agent_id, os.get_pid(), allocator = allocator)
		argv2 := []string{"git", "worktree", "add", "-b", branch, wt_root, base}
		out2, err2 := run_cmd(argv2, repo_root, context.temp_allocator)
		if len(err2) > 0 || strings.contains(out2, "fatal:") {
			info.err = fmt.aprintf("worktree create failed: %s %s", err, out, allocator = allocator)
			delete(branch)
			delete(wt_root)
			return info
		}
	}
	worktree_copy_includes(repo_root, wt_root)
	info.path = wt_root
	info.branch = branch
	info.ok = true
	return info
}

worktree_copy_includes :: proc(repo_root: string, wt_path: string) {
	inc, _ := filepath.join({repo_root, constants.WORKTREEINCLUDE_FILE}, context.temp_allocator)
	data, rerr := os.read_entire_file(inc, context.temp_allocator)
	if rerr != nil {
		return
	}
	lines := strings.split_lines(string(data), context.temp_allocator)
	for line in lines {
		p := strings.trim_space(line)
		if len(p) == 0 || strings.has_prefix(p, "#") {
			continue
		}
		src, _ := filepath.join({repo_root, p}, context.temp_allocator)
		dst, _ := filepath.join({wt_path, p}, context.temp_allocator)
		if bytes, berr := os.read_entire_file(src, context.temp_allocator); berr == nil {
			_ = sandbox.mkdir_all(filepath.dir(dst))
			_ = os.write_entire_file(dst, bytes)
		}
	}
}

worktree_has_changes :: proc(wt_path: string) -> bool {
	out, err := run_cmd([]string{"git", "status", "--porcelain"}, wt_path, context.temp_allocator)
	if len(err) > 0 {
		return true
	}
	return len(strings.trim_space(out)) > 0
}

worktree_diff_text :: proc(wt_path: string, max_chars: int, allocator := context.allocator) -> string {
	out, err := run_cmd([]string{"git", "diff", "HEAD"}, wt_path, context.temp_allocator)
	if len(err) > 0 {
		return strings.clone(err, allocator)
	}
	if len(out) > max_chars {
		return strings.clone(out[:max_chars], allocator)
	}
	return strings.clone(out, allocator)
}

WORKTREE_DIFF_UNTRACKED_MAX :: 8

/*
Head+tail cap for review diffs: keeps the first ~60% and last ~40% with a
marker line, since decision-relevant output (failures, tests) sits at the
tail. Cuts on newline boundaries when possible.
*/
truncate_head_tail :: proc(text: string, max_chars: int, allocator := context.allocator) -> string {
	if len(text) <= max_chars {
		return strings.clone(text, allocator)
	}
	if max_chars < 64 {
		return strings.clone(text[:max_chars], allocator)
	}
	head_len := max_chars * 3 / 5
	if idx := strings.last_index(text[:head_len], "\n"); idx > 0 {
		head_len = idx + 1
	}
	tail_start := len(text) - (max_chars - max_chars * 3 / 5)
	if idx := strings.index(text[tail_start:], "\n"); idx >= 0 {
		tail_start += idx + 1
	}
	if tail_start > len(text) || tail_start <= head_len {
		tail_start = head_len
	}
	return fmt.aprintf(
		"%s\n... [diff truncated: %d chars omitted] ...\n%s",
		text[:head_len],
		tail_start - head_len,
		text[tail_start:],
		allocator = allocator,
	)
}

/*
Review diff for a child worktree: merge-base of the base ref and the child
branch diffed against the worktree state, so committed branch commits and
uncommitted edits both show. Untracked files are appended as /dev/null diffs
(same trick as vcs.git_untracked_diffs) without touching the index. When the
worktree dir is already gone, falls back to a branch diff in repo_root.
*/
worktree_review_diff :: proc(
	repo_root: string,
	wt_path: string,
	branch: string,
	max_chars: int,
	allocator := context.allocator,
) -> (diff: string, err: string) {
	if len(branch) == 0 {
		return "", strings.clone("no worktree branch", allocator)
	}
	base := worktree_base_ref()
	mb := base
	if out, e := run_cmd([]string{"git", "merge-base", base, branch}, repo_root, context.temp_allocator); len(e) == 0 {
		if t := strings.trim_space(out); len(t) > 0 {
			mb = t
		}
	}
	b: strings.Builder
	strings.builder_init(&b, allocator)
	if len(wt_path) > 0 && os.is_dir(wt_path) {
		out, e := run_cmd([]string{"git", "diff", "--no-ext-diff", mb}, wt_path, context.temp_allocator)
		if len(e) > 0 {
			return "", fmt.aprintf("diff failed: %s %s", e, out, allocator = allocator)
		}
		strings.write_string(&b, out)
		if ulist, uerr := run_cmd([]string{"git", "ls-files", "-o", "--exclude-standard"}, wt_path, context.temp_allocator); len(uerr) == 0 {
			n := 0
			for line in strings.split_lines(ulist, context.temp_allocator) {
				p := strings.trim_space(line)
				if len(p) == 0 {
					continue
				}
				if n >= WORKTREE_DIFF_UNTRACKED_MAX {
					strings.write_string(&b, "... [more untracked files omitted]\n")
					break
				}
				piece, _ := run_cmd([]string{"git", "diff", "--no-ext-diff", "--no-index", "--", "/dev/null", p}, wt_path, context.temp_allocator)
				if len(strings.trim_space(piece)) == 0 {
					continue
				}
				strings.write_string(&b, piece)
				if !strings.has_suffix(piece, "\n") {
					strings.write_byte(&b, '\n')
				}
				n += 1
			}
		}
	} else {
		spec := fmt.tprintf("%s...%s", mb, branch)
		out, e := run_cmd([]string{"git", "diff", "--no-ext-diff", spec}, repo_root, context.temp_allocator)
		if len(e) > 0 {
			return "", fmt.aprintf("diff failed: %s %s", e, out, allocator = allocator)
		}
		strings.write_string(&b, out)
	}
	return truncate_head_tail(strings.to_string(b), max_chars, allocator), ""
}

worktree_remove_if_clean :: proc(repo_root: string, wt_path: string) -> bool {
	if worktree_has_changes(wt_path) {
		return false
	}
	_, err := run_cmd([]string{"git", "worktree", "remove", "--force", wt_path}, repo_root, context.temp_allocator)
	return len(err) == 0
}

worktree_apply_merge :: proc(
	repo_root: string,
	branch: string,
	allocator := context.allocator,
) -> (ok: bool, err: string) {
	out, e := run_cmd([]string{"git", "merge", "--no-edit", branch}, repo_root, context.temp_allocator)
	if len(e) > 0 || strings.contains(out, "CONFLICT") {
		return false, fmt.aprintf("merge failed: %s %s", e, out, allocator = allocator)
	}
	return true, ""
}

/*
Remove orphaned nullray worktrees under .nullray/worktrees when clean.
Also prune git worktree metadata. Safe: skips dirty trees unless force.
Returns how many removed.
*/
worktree_janitor :: proc(repo_root: string, force := false, allocator := context.allocator) -> (removed: int, report: string) {
	if !is_git_repo(repo_root) {
		return 0, strings.clone("not a git repo", allocator)
	}
	_, _ = run_cmd([]string{"git", "worktree", "prune"}, repo_root, context.temp_allocator)
	wt_root, _ := filepath.join({repo_root, constants.WORKTREES_DIR}, context.temp_allocator)
	entries, err := os.read_directory_by_path(wt_root, -1, context.temp_allocator)
	if err != nil {
		return 0, strings.clone("no worktrees dir", allocator)
	}
	b: strings.Builder
	strings.builder_init(&b, allocator)
	for e in entries {
		if e.type != .Directory {
			continue
		}
		path, _ := filepath.join({wt_root, e.name}, context.temp_allocator)
		if !force && worktree_has_changes(path) {
			fmt.sbprintf(&b, "skip dirty %s\n", e.name)
			continue
		}
		_, rerr := run_cmd([]string{"git", "worktree", "remove", "--force", path}, repo_root, context.temp_allocator)
		if len(rerr) == 0 {
			removed += 1
			fmt.sbprintf(&b, "removed %s\n", e.name)
			// drop local branch if present
			br := fmt.tprintf("nullray/%s", e.name)
			_, _ = run_cmd([]string{"git", "branch", "-D", br}, repo_root, context.temp_allocator)
		} else {
			fmt.sbprintf(&b, "failed %s: %s\n", e.name, rerr)
		}
	}
	if removed == 0 && strings.builder_len(b) == 0 {
		strings.write_string(&b, "nothing to clean\n")
	}
	return removed, strings.to_string(b)
}
