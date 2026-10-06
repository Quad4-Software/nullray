// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Best-of-N print samples. Each sample runs in a git worktree. The winner is
the first run that exits 0 with stopped=done, else the lowest exit code.
NULLRAY_VERIFY is turned on when unset so the verifier can pick.
*/

package run

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "nullray:constants"
import "nullray:sandbox"
import "nullray:subagent"

sample_score :: proc(r: Result) -> int {
	if r.exit_code == 0 && (r.stopped == "done" || len(r.stopped) == 0) {
		return 100
	}
	if r.stopped == "done" {
		return 50 - r.exit_code
	}
	return -r.exit_code
}

run_samples :: proc(cfg: Config) -> Result {
	n := cfg.samples
	if n < 2 {
		return run_print_inner(cfg)
	}
	if n > constants.SAMPLES_MAX {
		n = constants.SAMPLES_MAX
	}
	root := sandbox.workspace_current()
	if len(root) == 0 {
		if cwd, err := os.get_working_directory(context.temp_allocator); err == nil {
			root = cwd
		}
	}
	if !subagent.is_git_repo(root) {
		res: Result
		res.exit_code = 2
		res.err = strings.clone("--samples needs a git repository (worktrees)")
		return res
	}
	if _, ok := os.lookup_env(constants.ENV_VERIFY, context.temp_allocator); !ok {
		os.set_env(constants.ENV_VERIFY, "1")
	}
	best: Result
	best_score := -1_000_000
	best_path := ""
	best_branch := ""
	for i in 0 ..< n {
		id := fmt.tprintf("sample-%d", i + 1)
		info := subagent.worktree_create(id, root)
		if !info.ok {
			delete(info.path)
			delete(info.branch)
			delete(info.err)
			continue
		}
		sandbox.workspace_override_set(info.path)
		sub := cfg
		sub.samples = 1
		sub.architect = false
		r := run_print_inner(sub)
		sandbox.workspace_override_clear()
		sc := sample_score(r)
		fmt.eprintf("nullray: sample %d/%d score=%d stopped=%s exit=%d\n", i + 1, n, sc, r.stopped, r.exit_code)
		if sc > best_score {
			if len(best_path) > 0 {
				result_destroy(&best)
				_, _ = subagent.run_cmd([]string{"git", "worktree", "remove", "--force", best_path}, root, context.temp_allocator)
				delete(best_path)
				delete(best_branch)
			}
			best = r
			best_score = sc
			best_path = strings.clone(info.path)
			best_branch = strings.clone(info.branch)
		} else {
			result_destroy(&r)
			_, _ = subagent.run_cmd([]string{"git", "worktree", "remove", "--force", info.path}, root, context.temp_allocator)
		}
		delete(info.path)
		delete(info.branch)
		delete(info.err)
	}
	if len(best_path) == 0 {
		res: Result
		res.exit_code = 2
		res.err = strings.clone("no sample completed")
		return res
	}
	_ = samples_copy_winner(best_path, root)
	_, _ = subagent.run_cmd([]string{"git", "worktree", "remove", "--force", best_path}, root, context.temp_allocator)
	delete(best_path)
	delete(best_branch)
	return best
}

@(private)
samples_copy_winner :: proc(src, dst: string) -> bool {
	out, err := subagent.run_cmd([]string{"git", "diff", "--name-only", "HEAD"}, src, context.temp_allocator)
	if len(err) > 0 {
		return false
	}
	for line in strings.split_lines(out, context.temp_allocator) {
		rel := strings.trim_space(line)
		if len(rel) == 0 {
			continue
		}
		from, _ := filepath.join({src, rel}, context.temp_allocator)
		to, _ := filepath.join({dst, rel}, context.temp_allocator)
		data, rerr := os.read_entire_file(from, context.temp_allocator)
		if rerr != nil {
			continue
		}
		_ = sandbox.mkdir_all(filepath.dir(to))
		_ = os.write_entire_file(to, data)
	}
	return true
}
