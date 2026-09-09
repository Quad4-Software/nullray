// SPDX-License-Identifier: 0BSD
/*
Network and merge VCS operations.
*/

package vcs

import "core:fmt"
import "core:os"
import "core:strings"
import "nullray:constants"

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
