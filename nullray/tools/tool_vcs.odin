// SPDX-License-Identifier: 0BSD
package tools

import "core:fmt"
import "core:strings"
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
	revision, err := json_arg_string_optional(args_json, "revision", "", allocator)
	if err != "" {
		return "", err
	}
	defer delete(revision)
	repo := vcs_repo(allocator)
	defer vcs.repo_destroy(&repo)
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
	return vcs.commit(repo, message, allocator)
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
