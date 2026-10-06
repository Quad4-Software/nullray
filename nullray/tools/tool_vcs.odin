// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package tools

import "core:fmt"
import "core:strings"
import "nullray:constants"
import "nullray:provider"
import "nullray:subagent"
import "nullray:vcs"

vcs_repo :: proc(allocator := context.allocator) -> vcs.Repo {
	root := workspace_root(context.temp_allocator)
	return vcs.detect(root, allocator)
}

tool_vcs_status :: proc(args_json: string, allocator := context.allocator) -> (string, string) {
	_ = args_json
	repo := vcs_repo(allocator)
	defer vcs.repo_destroy(&repo)
	out, err := vcs.status(repo, allocator)
	if err != "" {
		return out, err
	}
	result := fmt.aprintf("vcs=%s\n%s", vcs.kind_name(repo.kind), out, allocator = allocator)
	delete(out)
	return result, ""
}

tool_vcs_diff :: proc(args_json: string, allocator := context.allocator) -> (string, string) {
	scope_s, serr := json_arg_string_optional(args_json, "scope", "", allocator)
	if serr != "" {
		return "", serr
	}
	defer delete(scope_s)
	base, berr := json_arg_string_optional(args_json, "base", "", allocator)
	if berr != "" {
		return "", berr
	}
	defer delete(base)
	revision, rerr := json_arg_string_optional(args_json, "revision", "", allocator)
	if rerr != "" {
		return "", rerr
	}
	defer delete(revision)
	paths_s, perr := json_arg_string_optional(args_json, "paths", "", allocator)
	if perr != "" {
		return "", perr
	}
	defer delete(paths_s)

	repo := vcs_repo(allocator)
	defer vcs.repo_destroy(&repo)

	if len(scope_s) > 0 || len(base) > 0 || len(paths_s) > 0 {
		scope := vcs.Diff_Scope.Working
		if len(scope_s) > 0 {
			s, ok := vcs.scope_from_string(scope_s)
			if !ok {
				return "", strings.clone("scope must be working|staged|unstaged|base", allocator)
			}
			scope = s
		}
		base_rev := base
		if len(base_rev) == 0 {
			base_rev = revision
		}
		if scope == .Base && len(strings.trim_space(base_rev)) == 0 {
			return "", strings.clone("base scope needs base or revision", allocator)
		}
		if len(base_rev) > 0 && scope == .Working && len(scope_s) == 0 {
			scope = .Base
		}
		path_list := make([dynamic]string, context.temp_allocator)
		if len(paths_s) > 0 {
			for p in strings.split(paths_s, ",", context.temp_allocator) {
				t := strings.trim_space(p)
				if len(t) > 0 {
					append(&path_list, t)
				}
			}
		}
		diff, label, err := vcs.collect_review_diff(
			repo,
			vcs.Diff_Opts{scope = scope, base = base_rev, paths = path_list[:]},
			allocator,
		)
		if err != "" {
			delete(label)
			return diff, err
		}
		out := fmt.aprintf("vcs=%s scope=%s\n%s", vcs.kind_name(repo.kind), label, diff, allocator = allocator)
		delete(diff)
		delete(label)
		return out, ""
	}

	return vcs.diff(repo, revision, allocator)
}

tool_vcs_log :: proc(args_json: string, allocator := context.allocator) -> (string, string) {
	count, err := json_arg_int_optional(args_json, "count", 20, allocator)
	if err != "" {
		return "", err
	}
	repo := vcs_repo(allocator)
	defer vcs.repo_destroy(&repo)
	return vcs.log(repo, count, allocator)
}

tool_vcs_commit :: proc(args_json: string, allocator := context.allocator) -> (string, string) {
	message, err := json_arg_string(args_json, "message", allocator)
	if err != "" {
		return "", err
	}
	defer delete(message)
	repo := vcs_repo(allocator)
	defer vcs.repo_destroy(&repo)
	model, provider_id, _ := subagent.session_bind_identity()
	method := provider_id
	if provider.provider_is_local(provider_id) {
		method = "Local"
	}
	return vcs.commit(repo, message, model, method, allocator)
}

tool_vcs_branch :: proc(args_json: string, allocator := context.allocator) -> (string, string) {
	name, err := json_arg_string_optional(args_json, "name", "", allocator)
	if err != "" {
		return "", err
	}
	defer delete(name)
	repo := vcs_repo(allocator)
	defer vcs.repo_destroy(&repo)
	return vcs.branch(repo, name, allocator)
}

tool_vcs_merge :: proc(args_json: string, allocator := context.allocator) -> (string, string) {
	target, err := json_arg_string(args_json, "target", allocator)
	if err != "" {
		return "", err
	}
	defer delete(target)
	allow_dirty_s, derr := json_arg_string_optional(args_json, "allow_dirty", "false", allocator)
	if derr != "" {
		return "", derr
	}
	defer delete(allow_dirty_s)
	allow_dirty := strings.to_lower(allow_dirty_s, context.temp_allocator) == "true"
	repo := vcs_repo(allocator)
	defer vcs.repo_destroy(&repo)
	return vcs.merge(repo, target, allow_dirty, allocator)
}

tool_vcs_rebase :: proc(args_json: string, allocator := context.allocator) -> (string, string) {
	target, err := json_arg_string(args_json, "target", allocator)
	if err != "" {
		return "", err
	}
	defer delete(target)
	allow_dirty_s, derr := json_arg_string_optional(args_json, "allow_dirty", "false", allocator)
	if derr != "" {
		return "", derr
	}
	defer delete(allow_dirty_s)
	allow_dirty := strings.to_lower(allow_dirty_s, context.temp_allocator) == "true"
	repo := vcs_repo(allocator)
	defer vcs.repo_destroy(&repo)
	return vcs.rebase(repo, target, allow_dirty, allocator)
}

tool_vcs_push :: proc(args_json: string, allocator := context.allocator) -> (string, string) {
	remote, err := json_arg_string_optional(args_json, "remote", "origin", allocator)
	if err != "" {
		return "", err
	}
	defer delete(remote)
	ref, rerr := json_arg_string_optional(args_json, "ref", "", allocator)
	if rerr != "" {
		return "", rerr
	}
	defer delete(ref)
	force_s, ferr := json_arg_string_optional(args_json, "force", "false", allocator)
	if ferr != "" {
		return "", ferr
	}
	defer delete(force_s)
	force := strings.to_lower(force_s, context.temp_allocator) == "true"
	repo := vcs_repo(allocator)
	defer vcs.repo_destroy(&repo)
	return vcs.push(repo, remote, ref, force, allocator)
}

tool_vcs_pull :: proc(args_json: string, allocator := context.allocator) -> (string, string) {
	remote, err := json_arg_string_optional(args_json, "remote", "origin", allocator)
	if err != "" {
		return "", err
	}
	defer delete(remote)
	ref, rerr := json_arg_string_optional(args_json, "ref", "", allocator)
	if rerr != "" {
		return "", rerr
	}
	defer delete(ref)
	repo := vcs_repo(allocator)
	defer vcs.repo_destroy(&repo)
	return vcs.pull(repo, remote, ref, allocator)
}

tool_vcs_fetch :: proc(args_json: string, allocator := context.allocator) -> (string, string) {
	remote, err := json_arg_string_optional(args_json, "remote", "origin", allocator)
	if err != "" {
		return "", err
	}
	defer delete(remote)
	repo := vcs_repo(allocator)
	defer vcs.repo_destroy(&repo)
	return vcs.fetch(repo, remote, allocator)
}

tool_vcs_pr_create :: proc(args_json: string, allocator := context.allocator) -> (string, string) {
	title, err := json_arg_string(args_json, "title", allocator)
	if err != "" {
		return "", err
	}
	defer delete(title)
	body, berr := json_arg_string_optional(args_json, "body", "", allocator)
	if berr != "" {
		return "", berr
	}
	defer delete(body)
	repo := vcs_repo(allocator)
	defer vcs.repo_destroy(&repo)
	return vcs.pr_create(repo, title, body, allocator)
}

tool_vcs_pr_view :: proc(args_json: string, allocator := context.allocator) -> (string, string) {
	_ = args_json
	repo := vcs_repo(allocator)
	defer vcs.repo_destroy(&repo)
	return vcs.pr_view(repo, allocator)
}

tool_vcs_pr_checks :: proc(args_json: string, allocator := context.allocator) -> (string, string) {
	_ = args_json
	repo := vcs_repo(allocator)
	defer vcs.repo_destroy(&repo)
	return vcs.pr_checks(repo, allocator)
}

tool_vcs_pr_watch :: proc(args_json: string, allocator := context.allocator) -> (string, string) {
	pr, perr := json_arg_string_optional(args_json, "pr", "", allocator)
	if perr != "" {
		return "", perr
	}
	defer delete(pr)
	wait_for, werr := json_arg_string_optional(args_json, "wait_for", "any", allocator)
	if werr != "" {
		return "", werr
	}
	defer delete(wait_for)
	switch wait_for {
	case "any", "checks", "comments":
	case:
		return "", strings.clone("wait_for must be any, checks, or comments", allocator)
	}
	timeout_sec, terr := json_arg_int_optional(args_json, "timeout_sec", 600, allocator)
	if terr != "" {
		return "", terr
	}
	if timeout_sec < 15 {
		timeout_sec = 15
	}
	if timeout_sec > constants.PR_WATCH_MAX_SEC {
		timeout_sec = constants.PR_WATCH_MAX_SEC
	}
	interval_sec, ierr := json_arg_int_optional(args_json, "interval_sec", 30, allocator)
	if ierr != "" {
		return "", ierr
	}
	if interval_sec < constants.PR_WATCH_INTERVAL_MIN_SEC {
		interval_sec = constants.PR_WATCH_INTERVAL_MIN_SEC
	}
	if interval_sec > 120 {
		interval_sec = 120
	}
	repo := vcs_repo(allocator)
	defer vcs.repo_destroy(&repo)
	return vcs.pr_watch(repo, pr, timeout_sec, interval_sec, wait_for, allocator)
}
