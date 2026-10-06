// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Shadow-git checkpoint helpers for workspace snapshots.
*/

package tools

import "core:fmt"
import "core:io"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:strings"
import "core:time"
import "nullray:crash"
import "nullray:sandbox"

@(private)
snapshot_run :: proc(argv: []string, cwd: string, allocator := context.allocator) -> (string, bool) {
	read_pipe, write_pipe, pipe_err := os.pipe()
	if pipe_err != nil {
		return "", false
	}
	defer os.close(read_pipe)
	process: os.Process
	{
		defer os.close(write_pipe)
		desc := os.Process_Desc{
			working_dir = cwd,
			command = argv,
			stdout = write_pipe,
			stderr = write_pipe,
		}
		start_err: os.Error
		process, start_err = os.process_start(desc)
		if start_err != nil {
			return "", false
		}
	}
	state, wait_err := os.process_wait(process)
	if wait_err != nil || !state.exited {
		return "", false
	}
	output: [dynamic]byte
	output.allocator = context.temp_allocator
	buffer: [4096]u8
	for {
		n, read_err := os.read(read_pipe, buffer[:])
		if n > 0 {
			append(&output, ..buffer[:n])
		}
		if n == 0 || read_err == io.Error.EOF || read_err == os.General_Error.Broken_Pipe {
			break
		}
		if read_err != nil {
			break
		}
	}
	return strings.clone(string(output[:]), allocator), state.exit_code == 0
}

@(private)
snapshot_git_args :: proc(dir, root: string, tail: []string, allocator := context.allocator) -> [dynamic]string {
	args := make([dynamic]string, 0, len(tail) + 3, allocator)
	append(&args, strings.clone("git", allocator))
	append(&args, fmt.aprintf("--git-dir=%s", dir, allocator = allocator))
	append(&args, fmt.aprintf("--work-tree=%s", root, allocator = allocator))
	for value in tail {
		append(&args, strings.clone(value, allocator))
	}
	return args
}

@(private)
snapshot_args_destroy :: proc(args: ^[dynamic]string) {
	for value in args {
		delete(value)
	}
	delete(args^)
	args^ = nil
}

@(private)
snapshot_git :: proc(dir, root: string, tail: []string, allocator := context.allocator) -> (string, bool) {
	args := snapshot_git_args(dir, root, tail, context.temp_allocator)
	return snapshot_run(args[:], root, allocator)
}

@(private)
snapshot_relative :: proc(abs_path, root: string) -> (string, bool) {
	if !strings.has_prefix(abs_path, root) {
		return "", false
	}
	relative := abs_path[len(root):]
	for len(relative) > 0 && (relative[0] == '/' || relative[0] == '\\') {
		relative = relative[1:]
	}
	return relative, len(relative) > 0
}

@(private)
snapshot_shadow_init :: proc(dir, root: string) -> bool {
	head, _ := filepath.join({dir, "HEAD"}, context.temp_allocator)
	if os.exists(head) {
		return true
	}
	// make_directory_all reports Exist when callers already created dir, so
	// judge by the result on disk, not the return code.
	_ = sandbox.mkdir_all(dir)
	if !os.is_dir(dir) {
		return false
	}
	out, ok := snapshot_git(dir, root, []string{"init"}, context.temp_allocator)
	if !ok {
		crash.logf("shadow init failed: %s", out)
		return false
	}
	_, _ = snapshot_git(dir, root, []string{"config", "user.name", "nullray"}, context.temp_allocator)
	_, _ = snapshot_git(dir, root, []string{"config", "user.email", "nullray@localhost"}, context.temp_allocator)
	return true
}

@(private)
snapshot_shadow_create :: proc(
	abs_path, dir, root: string,
	allocator := context.allocator,
) -> (commit, ref_name: string, ok: bool) {
	relative, rel_ok := snapshot_relative(abs_path, root)
	if !rel_ok || !snapshot_shadow_init(dir, root) {
		return "", "", false
	}
	out, add_ok := snapshot_git(dir, root, []string{"add", "-f", "-A", "--", relative}, context.temp_allocator)
	if !add_ok {
		crash.logf("shadow add failed: %s", out)
		return "", "", false
	}
	tree_out, tree_ok := snapshot_git(dir, root, []string{"write-tree"}, context.temp_allocator)
	if !tree_ok {
		crash.logf("shadow write-tree failed: %s", tree_out)
		return "", "", false
	}
	tree := strings.trim_space(tree_out)
	commit_out, commit_ok := snapshot_git(
		dir,
		root,
		[]string{"commit-tree", tree, "-m", "nullray checkpoint"},
		context.temp_allocator,
	)
	if !commit_ok {
		crash.logf("shadow commit-tree failed: %s", commit_out)
		return "", "", false
	}
	hash := strings.trim_space(commit_out)
	ref := fmt.tprintf(
		"refs/nullray/%d-%d-%d",
		time.time_to_unix(time.now()),
		os.get_pid(),
		g_snap_id,
	)
	rout, ref_ok := snapshot_git(dir, root, []string{"update-ref", ref, hash}, context.temp_allocator)
	if !ref_ok {
		crash.logf("shadow update-ref failed: %s", rout)
		return "", "", false
	}
	return strings.clone(hash, allocator), strings.clone(ref, allocator), true
}

/*
Commit the staged index as a standalone batch anchor under
refs/nullray/ckpt-<id>. The index still holds pre-write content for the
batch's files, so the anchor tree is the pre-batch state used by restore.
Parentless on purpose: anchoring to a parent would keep every older
checkpoint reachable forever and defeat pruning.
*/
@(private)
snapshot_shadow_commit :: proc(
	dir, root: string,
	id: u64,
	message: string,
	allocator := context.allocator,
) -> (commit, ref_name: string) {
	if !snapshot_shadow_init(dir, root) {
		return "", ""
	}
	tree_out, tree_ok := snapshot_git(dir, root, []string{"write-tree"}, context.temp_allocator)
	if !tree_ok {
		return "", ""
	}
	tree := strings.trim_space(tree_out)
	commit_out, commit_ok := snapshot_git(
		dir,
		root,
		[]string{"commit-tree", tree, "-m", message},
		context.temp_allocator,
	)
	if !commit_ok {
		return "", ""
	}
	hash := strings.trim_space(commit_out)
	ref := fmt.tprintf("refs/nullray/ckpt-%d", id)
	_, ref_ok := snapshot_git(dir, root, []string{"update-ref", ref, hash}, context.temp_allocator)
	if !ref_ok {
		return "", ""
	}
	return strings.clone(hash, allocator), strings.clone(ref, allocator)
}

/*
Loose plus packed object size in KiB from git count-objects -v. Loose bytes
are the size: field, packed bytes are size-pack:. Returns 0 when git fails or
the repo is missing.
*/
@(private)
snapshot_shadow_size_kb :: proc(dir, root: string) -> i64 {
	out, ok := snapshot_git(dir, root, []string{"count-objects", "-v"}, context.temp_allocator)
	if !ok {
		return 0
	}
	total: i64 = 0
	for line in strings.split_lines(out, context.temp_allocator) {
		line := strings.trim_space(line)
		value := ""
		if strings.has_prefix(line, "size-pack:") {
			value = strings.trim_space(line[len("size-pack:"):])
		} else if strings.has_prefix(line, "size:") {
			value = strings.trim_space(line[len("size:"):])
		} else {
			continue
		}
		if n, parsed := strconv.parse_i64(value); parsed {
			total += n
		}
	}
	return total
}
