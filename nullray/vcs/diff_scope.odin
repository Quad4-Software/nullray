// SPDX-License-Identifier: 0BSD
/*
Local review diff scopes for Git and Fossil (no forge required).
*/

package vcs

import "core:fmt"
import "core:strings"

Diff_Scope :: enum {
	Working, // tracked changes vs HEAD (staged + unstaged)
	Staged,
	Unstaged,
	Base, // vs base revision / branch
}

Diff_Opts :: struct {
	scope:              Diff_Scope,
	base:               string,
	paths:              []string,
	include_untracked:  bool,
}

scope_name :: proc(scope: Diff_Scope) -> string {
	switch scope {
	case .Working:
		return "working"
	case .Staged:
		return "staged"
	case .Unstaged:
		return "unstaged"
	case .Base:
		return "base"
	}
	return "working"
}

scope_from_string :: proc(s: string) -> (Diff_Scope, bool) {
	switch strings.to_lower(strings.trim_space(s), context.temp_allocator) {
	case "working", "tracked", "all", "":
		return .Working, true
	case "staged", "cached", "index":
		return .Staged, true
	case "unstaged", "dirty", "uncommitted":
		return .Unstaged, true
	case "base", "branch", "committed":
		return .Base, true
	}
	return .Working, false
}

/*
Collect a reviewable unified diff. Caller owns the returned strings.
label describes the scope for prompts (for example working vs HEAD).
*/
collect_review_diff :: proc(
	repo: Repo,
	opts: Diff_Opts,
	allocator := context.allocator,
) -> (
	diff: string,
	label: string,
	err: string,
) {
	if repo.kind == .None {
		return "", "", strings.clone("no Git or Fossil repository detected", allocator)
	}
	base := strings.trim_space(opts.base)
	if opts.scope == .Base && len(base) == 0 {
		return "", "", strings.clone("base scope needs a revision or branch (use --base)", allocator)
	}

	argv := make([dynamic]string, context.temp_allocator)
	lab: string
	switch repo.kind {
	case .Git:
		append(&argv, "git", "diff", "--no-ext-diff")
		switch opts.scope {
		case .Working:
			append(&argv, "HEAD")
			lab = "working (staged+unstaged vs HEAD)"
		case .Staged:
			append(&argv, "--cached")
			lab = "staged"
		case .Unstaged:
			lab = "unstaged"
		case .Base:
			append(&argv, fmt.tprintf("%s...HEAD", base))
			lab = fmt.tprintf("base %s...HEAD", base)
		}
		if len(opts.paths) > 0 {
			append(&argv, "--")
			for p in opts.paths {
				t := strings.trim_space(p)
				if len(t) > 0 {
					append(&argv, t)
				}
			}
		}
	case .Fossil:
		append(&argv, "fossil", "diff")
		switch opts.scope {
		case .Working, .Staged, .Unstaged:
			lab = "working"
		case .Base:
			append(&argv, "--from", base)
			lab = fmt.tprintf("base %s", base)
		}
		for p in opts.paths {
			t := strings.trim_space(p)
			if len(t) > 0 {
				append(&argv, t)
			}
		}
	case .None:
		unreachable()
	}

	out, rerr := run(repo, argv[:], allocator)
	if rerr != "" {
		return out, "", strings.clone(rerr, allocator)
	}

	if opts.include_untracked && repo.kind == .Git && (opts.scope == .Working || opts.scope == .Unstaged) {
		extra, eerr := git_untracked_diffs(repo, opts.paths, allocator)
		if eerr != "" {
			delete(out)
			return "", "", eerr
		}
		if len(extra) > 0 {
			combined := strings.concatenate({out, "\n", extra}, allocator)
			delete(out)
			delete(extra)
			out = combined
			lab = fmt.tprintf("%s +untracked", lab)
		} else {
			delete(extra)
		}
	}

	return out, strings.clone(lab, allocator), ""
}

git_untracked_diffs :: proc(
	repo: Repo,
	paths: []string,
	allocator := context.allocator,
) -> (
	string,
	string,
) {
	list, lerr := run(repo, {"git", "ls-files", "-o", "--exclude-standard"}, context.temp_allocator)
	if lerr != "" {
		return "", strings.clone(lerr, allocator)
	}
	b: strings.Builder
	strings.builder_init(&b, allocator)
	for line in strings.split_lines(list, context.temp_allocator) {
		path := strings.trim_space(line)
		if len(path) == 0 {
			continue
		}
		if len(paths) > 0 && !path_in_filters(path, paths) {
			continue
		}
		piece, perr := run(repo, {"git", "diff", "--no-ext-diff", "--no-index", "--", "/dev/null", path}, context.temp_allocator)
		// git diff --no-index exits 1 when files differ and still prints a useful diff.
		if len(strings.trim_space(piece)) == 0 {
			continue
		}
		if perr != "" && !strings.contains(piece, "diff --git") && !strings.contains(piece, "--- /dev/null") {
			continue
		}
		strings.write_string(&b, piece)
		if !strings.has_suffix(piece, "\n") {
			strings.write_byte(&b, '\n')
		}
	}
	return strings.to_string(b), ""
}

path_in_filters :: proc(path: string, filters: []string) -> bool {
	for f in filters {
		t := strings.trim_space(f)
		if len(t) == 0 {
			continue
		}
		if path == t {
			return true
		}
		// Directory prefix: "dir" or "dir/" matches "dir/file"
		prefix := t
		if strings.has_suffix(prefix, "/") {
			prefix = prefix[:len(prefix) - 1]
		}
		if len(path) > len(prefix) && strings.has_prefix(path, prefix) && path[len(prefix)] == '/' {
			return true
		}
	}
	return false
}
