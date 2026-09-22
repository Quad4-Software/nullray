// SPDX-License-Identifier: 0BSD
/*
Network and merge VCS operations.
*/

package vcs

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:time"
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

pr_checks :: proc(repo: Repo, allocator := context.allocator) -> (string, string) {
	if err := require_network(allocator); err != "" {
		return "", err
	}
	if repo.kind != .Git {
		return "", strings.clone("PR helpers require Git and the gh CLI", allocator)
	}
	out, _ := run(repo, {"gh", "pr", "checks"}, context.temp_allocator)
	if len(strings.trim_space(out)) == 0 {
		return strings.clone("no checks reported", allocator), ""
	}
	return strings.clone(out, allocator), ""
}

/*
Poll gh pr checks and PR comment/review endpoints until an actionable event
or the deadline. The loop lives inside the tool so waiting costs no model
steps. wait_for: any (checks to terminal state or new comments) | checks |
comments (comments only; check state still reported). Returns a compact
report whose first line is status= checks_failed | checks_done |
new_activity | timeout.
*/
pr_watch :: proc(
	repo: Repo,
	pr: string,
	timeout_sec, interval_sec: int,
	wait_for: string,
	allocator := context.allocator,
) -> (string, string) {
	if err := require_network(allocator); err != "" {
		return "", err
	}
	if repo.kind != .Git {
		return "", strings.clone("PR helpers require Git and the gh CLI", allocator)
	}
	// gh pr view accepts a number, URL, or branch name and resolves all of
	// them, so always normalize to the PR number before building endpoints.
	num_args: []string
	if len(strings.trim_space(pr)) > 0 {
		num_args = {strings.trim_space(pr)}
	}
	argv := make([dynamic]string, context.temp_allocator)
	append(&argv, "gh", "pr", "view")
	append(&argv, ..num_args)
	append(&argv, "--json", "number", "--jq", ".number")
	out0, err0 := run(repo, argv[:], context.temp_allocator)
	num := ""
	for line in strings.split_lines(out0, context.temp_allocator) {
		cand := strings.trim_space(line)
		if _, ok := strconv.parse_int(cand); ok {
			num = cand
			break
		}
	}
	if err0 != "" || len(num) == 0 {
		return "", strings.clone("no PR found (tried current branch and the pr argument)", allocator)
	}
	// Build endpoints without fmt: the gh api {owner}/{repo} placeholders
	// collide with fmt format-option braces.
	issue_ep := strings.concatenate({"repos/{owner}/{repo}/issues/", num, "/comments"}, context.temp_allocator)
	pulls_ep := strings.concatenate({"repos/{owner}/{repo}/pulls/", num, "/comments"}, context.temp_allocator)
	review_ep := strings.concatenate({"repos/{owner}/{repo}/pulls/", num, "/reviews"}, context.temp_allocator)
	base_issue := gh_max_id(repo, issue_ep)
	base_pulls := gh_max_id(repo, pulls_ep)
	base_review := gh_max_id(repo, review_ep)

	wait_checks := wait_for == "any" || wait_for == "checks"
	wait_comments := wait_for == "any" || wait_for == "comments"
	deadline := time.now()
	status := "timeout"
	checks_text := ""
	api_errors := 0
	activity: strings.Builder
	strings.builder_init(&activity, context.temp_allocator)

	for {
		out, _ := run(repo, {"gh", "pr", "checks", num}, context.temp_allocator)
		checks_text = out
		pending, failed, _ := check_state_counts(out)
		if wait_checks && failed > 0 {
			status = "checks_failed"
			break
		}
		if pending == 0 && wait_checks {
			status = "checks_done"
			break
		}
		if wait_comments {
			new_activity := false
			// A negative mark means the gh api call failed (often a
			// secondary rate limit). Skip it, and if the baseline itself
			// failed, adopt the first successful mark as baseline instead
			// of reporting every pre-existing comment as new.
			if mark := gh_max_id(repo, issue_ep); mark < 0 {
				api_errors += 1
			} else if base_issue < 0 {
				base_issue = mark
			} else if mark > base_issue {
				gh_activity_since(repo, issue_ep, `"[issue-comment] @\(.user.login) (\(.created_at)): \(.body[:1500])"`, base_issue, &activity)
				base_issue = mark
				new_activity = true
			}
			if mark := gh_max_id(repo, pulls_ep); mark < 0 {
				api_errors += 1
			} else if base_pulls < 0 {
				base_pulls = mark
			} else if mark > base_pulls {
				gh_activity_since(repo, pulls_ep, `"[review-comment] @\(.user.login) \(.path // ""):\(.line // .original_line // 0) (\(.created_at)): \(.body[:1500])"`, base_pulls, &activity)
				base_pulls = mark
				new_activity = true
			}
			if mark := gh_max_id(repo, review_ep); mark < 0 {
				api_errors += 1
			} else if base_review < 0 {
				base_review = mark
			} else if mark > base_review {
				gh_activity_since(repo, review_ep, `"[review] @\(.user.login) \(.state) (\(.submitted_at)): \(.body[:1500])"`, base_review, &activity)
				base_review = mark
				new_activity = true
			}
			if new_activity {
				status = "new_activity"
				break
			}
		}
		if time.since(deadline) >= time.Second * time.Duration(timeout_sec) {
			break
		}
		time.sleep(time.Second * time.Duration(interval_sec))
	}

	b: strings.Builder
	strings.builder_init(&b, allocator)
	strings.write_string(&b, "status=")
	strings.write_string(&b, status)
	strings.write_string(&b, " pr=")
	strings.write_string(&b, num)
	if api_errors > 0 {
		strings.write_string(&b, " api_errors=")
		strings.write_string(&b, fmt.tprintf("%d", api_errors))
	}
	strings.write_string(&b, "\nchecks:\n")
	ct := strings.trim_space(checks_text)
	strings.write_string(&b, len(ct) > 0 ? ct : "(none reported)")
	if strings.builder_len(activity) > 0 {
		strings.write_string(&b, "\nnew activity:\n")
		strings.write_string(&b, strings.to_string(activity))
	}
	return strings.to_string(b), ""
}

@(private)
gh_max_id :: proc(repo: Repo, endpoint: string) -> int {
	out, err := run(repo, {"gh", "api", endpoint, "--paginate", "--jq", "[.[].id] | max // 0"}, context.temp_allocator)
	if err != "" {
		return -1
	}
	n, ok := strconv.parse_int(strings.trim_space(out))
	if !ok {
		return -1
	}
	return n
}

@(private)
gh_activity_since :: proc(repo: Repo, endpoint, jq_tmpl: string, base: int, b: ^strings.Builder) {
	jq := fmt.tprintf(".[] | select(.id > %d) | %s", base, jq_tmpl)
	out, _ := run(repo, {"gh", "api", endpoint, "--paginate", "--jq", jq}, context.temp_allocator)
	for line in strings.split_lines(out, context.temp_allocator) {
		if strings.builder_len(b^) > 8000 {
			return
		}
		strings.write_string(b, line)
		strings.write_string(b, "\n")
	}
}

@(private)
check_state_counts :: proc(out: string) -> (pending, failed, total: int) {
	for line in strings.split_lines(out, context.temp_allocator) {
		fields := strings.split(line, "\t", context.temp_allocator)
		if len(fields) < 2 {
			continue
		}
		total += 1
		st := strings.to_lower(strings.trim_space(fields[1]), context.temp_allocator)
		switch st {
		case "fail", "failure", "cancel", "cancelled", "timed_out", "error", "action_required", "startup_failure":
			failed += 1
		case "pending", "queued", "waiting", "in_progress", "requested", "expected":
			pending += 1
		}
	}
	return
}
