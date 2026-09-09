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
