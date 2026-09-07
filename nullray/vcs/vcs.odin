// SPDX-License-Identifier: 0BSD
/*
Local Git and Fossil operations. Network ops need NULLRAY_VCS_NETWORK=1.
*/

package vcs

import "core:fmt"
import "core:io"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:strings"
import "core:time"
import "nullray:constants"

Kind :: enum {
	None,
	Git,
	Fossil,
}

Repo :: struct {
	kind: Kind,
	root: string,
}

detect :: proc(root: string, allocator := context.allocator) -> Repo {
	override := ""
	if v, ok := os.lookup_env(constants.ENV_VCS, context.temp_allocator); ok {
		override = strings.to_lower(strings.trim_space(v), context.temp_allocator)
	}
	git_path, _ := filepath.join({root, ".git"}, context.temp_allocator)
	fossil_path, _ := filepath.join({root, ".fslckout"}, context.temp_allocator)
	fossil_alt, _ := filepath.join({root, "_FOSSIL_"}, context.temp_allocator)
	has_git := os.exists(git_path)
	has_fossil := os.exists(fossil_path) || os.exists(fossil_alt)
	kind := Kind.None
	switch override {
	case "git":
		if has_git {
			kind = .Git
		}
	case "fossil":
		if has_fossil {
			kind = .Fossil
		}
	case "none", "off":
		kind = .None
	case:
		if has_git {
			kind = .Git
		} else if has_fossil {
			kind = .Fossil
		}
	}
	return Repo{kind = kind, root = strings.clone(root, allocator)}
}

repo_destroy :: proc(repo: ^Repo) {
	if repo == nil {
		return
	}
	delete(repo.root)
	repo^ = {}
}

kind_name :: proc(kind: Kind) -> string {
	switch kind {
	case .Git:
		return "git"
	case .Fossil:
		return "fossil"
	case .None:
		return "none"
	}
	return "none"
}

status :: proc(repo: Repo, allocator := context.allocator) -> (string, string) {
	switch repo.kind {
	case .Git:
		return run(repo, {"git", "status", "--short", "--branch"}, allocator)
	case .Fossil:
		return run(repo, {"fossil", "status"}, allocator)
	case .None:
		return "", strings.clone("no Git or Fossil repository detected", allocator)
	}
	return "", strings.clone("unknown VCS", allocator)
}

diff :: proc(repo: Repo, revision := "", allocator := context.allocator) -> (string, string) {
	switch repo.kind {
	case .Git:
		if len(revision) > 0 {
			return run(repo, {"git", "diff", "--no-ext-diff", revision}, allocator)
		}
		return run(repo, {"git", "diff", "--no-ext-diff"}, allocator)
	case .Fossil:
		if len(revision) > 0 {
			return run(repo, {"fossil", "diff", "--from", revision}, allocator)
		}
		return run(repo, {"fossil", "diff"}, allocator)
	case .None:
		return "", strings.clone("no Git or Fossil repository detected", allocator)
	}
	return "", strings.clone("unknown VCS", allocator)
}

log :: proc(repo: Repo, count: int = 20, allocator := context.allocator) -> (string, string) {
	entry_count := count
	if entry_count <= 0 {
		entry_count = 20
	}
	n_buf: [32]byte
	n := strconv.write_int(n_buf[:], i64(entry_count), 10)
	switch repo.kind {
	case .Git:
		return run(repo, {"git", "log", "--oneline", "--decorate", "-n", n}, allocator)
	case .Fossil:
		return run(repo, {"fossil", "timeline", "-n", n, "-t", "ci"}, allocator)
	case .None:
		return "", strings.clone("no Git or Fossil repository detected", allocator)
	}
	return "", strings.clone("unknown VCS", allocator)
}

commit :: proc(repo: Repo, message: string, allocator := context.allocator) -> (string, string) {
	if len(strings.trim_space(message)) == 0 {
		return "", strings.clone("commit message is required", allocator)
	}
	switch repo.kind {
	case .Git:
		return run(repo, {"git", "commit", "-m", message}, allocator)
	case .Fossil:
		return run(repo, {"fossil", "commit", "-m", message}, allocator)
	case .None:
		return "", strings.clone("no Git or Fossil repository detected", allocator)
	}
	return "", strings.clone("unknown VCS", allocator)
}

branch :: proc(repo: Repo, name := "", allocator := context.allocator) -> (string, string) {
	switch repo.kind {
	case .Git:
		if len(name) == 0 {
			return run(repo, {"git", "branch", "--show-current"}, allocator)
		}
		return run(repo, {"git", "switch", "-c", name}, allocator)
	case .Fossil:
		if len(name) == 0 {
			return run(repo, {"fossil", "branch", "current"}, allocator)
		}
		current, cerr := run(repo, {"fossil", "info", "current"}, context.temp_allocator)
		if cerr != "" {
			return "", strings.clone(cerr, allocator)
		}
		base := strings.trim_space(current)
		if len(base) == 0 {
			base = "trunk"
		}
		out, err := run(repo, {"fossil", "branch", "new", name, base}, allocator)
		if err != "" {
			return out, err
		}
		delete(out)
		return run(repo, {"fossil", "update", name}, allocator)
	case .None:
		return "", strings.clone("no Git or Fossil repository detected", allocator)
	}
	return "", strings.clone("unknown VCS", allocator)
}

dirty :: proc(repo: Repo) -> bool {
	switch repo.kind {
	case .Git:
		out, err := run(repo, {"git", "status", "--porcelain"}, context.temp_allocator)
		return err != "" || len(strings.trim_space(out)) > 0
	case .Fossil:
		out, err := run(repo, {"fossil", "changes", "--differ"}, context.temp_allocator)
		return err != "" || len(strings.trim_space(out)) > 0
	case .None:
		return false
	}
	return false
}

merge :: proc(repo: Repo, target: string, allow_dirty := false, allocator := context.allocator) -> (string, string) {
	if len(strings.trim_space(target)) == 0 {
		return "", strings.clone("merge target is required", allocator)
	}
	if !allow_dirty && dirty(repo) {
		return "", strings.clone("merge refused because the working tree is dirty", allocator)
	}
	switch repo.kind {
	case .Git:
		return run(repo, {"git", "merge", target}, allocator)
	case .Fossil:
		return run(repo, {"fossil", "merge", target}, allocator)
	case .None:
		return "", strings.clone("no Git or Fossil repository detected", allocator)
	}
	return "", strings.clone("unknown VCS", allocator)
}

rebase :: proc(repo: Repo, target: string, allow_dirty := false, allocator := context.allocator) -> (string, string) {
	if repo.kind != .Git {
		return "", strings.clone("rebase is supported for Git only", allocator)
	}
	if len(strings.trim_space(target)) == 0 {
		return "", strings.clone("rebase target is required", allocator)
	}
	if !allow_dirty && dirty(repo) {
		return "", strings.clone("rebase refused because the working tree is dirty", allocator)
	}
	return run(repo, {"git", "rebase", target}, allocator)
}

network_allowed :: proc() -> bool {
	if v, ok := os.lookup_env(constants.ENV_VCS_NETWORK, context.temp_allocator); ok {
		switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
		case "1", "true", "yes", "on":
			return true
		}
	}
	return false
}

force_allowed :: proc() -> bool {
	if v, ok := os.lookup_env(constants.ENV_VCS_FORCE, context.temp_allocator); ok {
		switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
		case "1", "true", "yes", "on":
			return true
		}
	}
	return false
}

require_network :: proc(allocator := context.allocator) -> string {
	if network_allowed() {
		return ""
	}
	return strings.clone("VCS network disabled. Set NULLRAY_VCS_NETWORK=1 to allow push/pull/fetch/PR", allocator)
}

push :: proc(repo: Repo, remote := "origin", ref := "", force := false, allocator := context.allocator) -> (string, string) {
	if err := require_network(allocator); err != "" {
		return "", err
	}
	if force && !force_allowed() {
		branch := ref
		if len(branch) == 0 {
			cur, _ := run(repo, {"git", "branch", "--show-current"}, context.temp_allocator)
			branch = strings.trim_space(cur)
		}
		lower := strings.to_lower(branch, context.temp_allocator)
		if lower == "main" || lower == "master" || strings.has_suffix(lower, "/main") || strings.has_suffix(lower, "/master") {
			return "", strings.clone("force-push to main/master blocked. Set NULLRAY_VCS_FORCE=1", allocator)
		}
	}
	switch repo.kind {
	case .Git:
		args := make([dynamic]string, context.temp_allocator)
		append(&args, "git", "push")
		if force {
			append(&args, "--force-with-lease")
		}
		append(&args, remote)
		if len(ref) > 0 {
			append(&args, ref)
		}
		return run(repo, args[:], allocator)
	case .Fossil:
		return run(repo, {"fossil", "push"}, allocator)
	case .None:
		return "", strings.clone("no Git or Fossil repository detected", allocator)
	}
	return "", strings.clone("unknown VCS", allocator)
}

pull :: proc(repo: Repo, remote := "origin", ref := "", allocator := context.allocator) -> (string, string) {
	if err := require_network(allocator); err != "" {
		return "", err
	}
	switch repo.kind {
	case .Git:
		if len(ref) > 0 {
			return run(repo, {"git", "pull", remote, ref}, allocator)
		}
		return run(repo, {"git", "pull", remote}, allocator)
	case .Fossil:
		return run(repo, {"fossil", "pull"}, allocator)
	case .None:
		return "", strings.clone("no Git or Fossil repository detected", allocator)
	}
	return "", strings.clone("unknown VCS", allocator)
}

fetch :: proc(repo: Repo, remote := "origin", allocator := context.allocator) -> (string, string) {
	if err := require_network(allocator); err != "" {
		return "", err
	}
	switch repo.kind {
	case .Git:
		return run(repo, {"git", "fetch", remote}, allocator)
	case .Fossil:
		return run(repo, {"fossil", "pull"}, allocator)
	case .None:
		return "", strings.clone("no Git or Fossil repository detected", allocator)
	}
	return "", strings.clone("unknown VCS", allocator)
}

pr_create :: proc(repo: Repo, title: string, body: string, allocator := context.allocator) -> (string, string) {
	if err := require_network(allocator); err != "" {
		return "", err
	}
	if repo.kind != .Git {
		return "", strings.clone("PR helpers require Git and the gh CLI", allocator)
	}
	if len(strings.trim_space(title)) == 0 {
		return "", strings.clone("PR title is required", allocator)
	}
	args := make([dynamic]string, context.temp_allocator)
	append(&args, "gh", "pr", "create", "--title", title)
	if len(body) > 0 {
		append(&args, "--body", body)
	} else {
		append(&args, "--body", "")
	}
	return run(repo, args[:], allocator)
}

pr_view :: proc(repo: Repo, allocator := context.allocator) -> (string, string) {
	if err := require_network(allocator); err != "" {
		return "", err
	}
	if repo.kind != .Git {
		return "", strings.clone("PR helpers require Git and the gh CLI", allocator)
	}
	return run(repo, {"gh", "pr", "view"}, allocator)
}

@(private)
run :: proc(repo: Repo, argv: []string, allocator := context.allocator) -> (out: string, err: string) {
	stdout_r, stdout_w, pipe_err := os.pipe()
	if pipe_err != nil {
		return "", fmt.aprintf("VCS pipe failed: %v", pipe_err, allocator = allocator)
	}
	defer os.close(stdout_r)
	stderr_r, stderr_w, pipe_err2 := os.pipe()
	if pipe_err2 != nil {
		return "", fmt.aprintf("VCS pipe failed: %v", pipe_err2, allocator = allocator)
	}
	defer os.close(stderr_r)

	process: os.Process
	{
		defer os.close(stdout_w)
		defer os.close(stderr_w)
		desc := os.Process_Desc{
			working_dir = repo.root,
			command = argv,
			stdout = stdout_w,
			stderr = stderr_w,
		}
		start_err: os.Error
		process, start_err = os.process_start(desc)
		if start_err != nil {
			return "", fmt.aprintf("VCS exec failed: %v", start_err, allocator = allocator)
		}
	}

	stdout_b := make([dynamic]byte, context.temp_allocator)
	stderr_b := make([dynamic]byte, context.temp_allocator)
	buf: [2048]u8
	start := time.now()
	timed_out := false
	exited := false
	exit_code := 0
	for !exited {
		has_stdout, _ := os.pipe_has_data(stdout_r)
		if has_stdout {
			n, _ := os.read(stdout_r, buf[:])
			if n > 0 {
				append(&stdout_b, ..buf[:n])
			}
		}
		has_stderr, _ := os.pipe_has_data(stderr_r)
		if has_stderr {
			n, _ := os.read(stderr_r, buf[:])
			if n > 0 {
				append(&stderr_b, ..buf[:n])
			}
		}
		state, wait_err := os.process_wait(process, 0)
		if wait_err == nil && state.exited {
			exited = true
			exit_code = state.exit_code
			break
		}
		if time.since(start) >= time.Second * 30 {
			timed_out = true
			_ = os.process_kill(process)
			state, _ = os.process_wait(process)
			exited = true
			exit_code = state.exit_code
		}
	}
	for {
		n, rerr := os.read(stdout_r, buf[:])
		if n > 0 {
			append(&stdout_b, ..buf[:n])
		}
		if n == 0 || rerr == io.Error.EOF || rerr == os.General_Error.Broken_Pipe {
			break
		}
	}
	for {
		n, rerr := os.read(stderr_r, buf[:])
		if n > 0 {
			append(&stderr_b, ..buf[:n])
		}
		if n == 0 || rerr == io.Error.EOF || rerr == os.General_Error.Broken_Pipe {
			break
		}
	}
	combined := fmt.aprintf("%s%s", string(stdout_b[:]), string(stderr_b[:]), allocator = allocator)
	if timed_out {
		return combined, strings.clone("VCS command timed out", allocator)
	}
	if exit_code != 0 {
		return combined, fmt.aprintf("VCS command failed with exit %d: %s", exit_code, combined, allocator = allocator)
	}
	return combined, ""
}
