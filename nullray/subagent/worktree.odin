// SPDX-License-Identifier: 0BSD
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

Worktree_Info :: struct {
	path:   string,
	branch: string,
	ok:     bool,
	err:    string,
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

	stdout_b: [dynamic]byte
	stdout_b.allocator = context.temp_allocator
	stderr_b: [dynamic]byte
	stderr_b.allocator = context.temp_allocator
	buf: [1024]u8
	timeout := time.Millisecond * 30_000
	start := time.now()
	stdout_done := false
	stderr_done := false

	for !stdout_done || !stderr_done {
		if time.since(start) >= timeout {
			_ = os.process_kill(process)
			break
		}
		if !stdout_done {
			has_data, _ := os.pipe_has_data(stdout_r)
			if has_data {
				n, rerr := os.read(stdout_r, buf[:])
				if n > 0 {
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
					append(&stderr_b, ..buf[:n])
				}
				if rerr == io.Error.EOF || rerr == os.General_Error.Broken_Pipe {
					stderr_done = true
				}
			}
		}
		wait_state, wait_err := os.process_wait(process, 0)
		if wait_err == nil && wait_state.exited {
			for !stdout_done {
				n, rerr := os.read(stdout_r, buf[:])
				if n > 0 {
					append(&stdout_b, ..buf[:n])
				}
				if n == 0 || rerr == io.Error.EOF || rerr == os.General_Error.Broken_Pipe {
					stdout_done = true
				}
			}
			for !stderr_done {
				n, rerr := os.read(stderr_r, buf[:])
				if n > 0 {
					append(&stderr_b, ..buf[:n])
				}
				if n == 0 || rerr == io.Error.EOF || rerr == os.General_Error.Broken_Pipe {
					stderr_done = true
				}
			}
			break
		}
	}

	state, _ := os.process_wait(process)
	if !state.exited {
		_ = os.process_kill(process)
		state, _ = os.process_wait(process)
	}
	combined := fmt.aprintf("%s%s", string(stdout_b[:]), string(stderr_b[:]), allocator = allocator)
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
	_ = os.make_directory_all(wt_parent)

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
			_ = os.make_directory_all(filepath.dir(dst))
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
